#!/usr/bin/env bash
# Inferencia completa na simulacao do SoC (sem a placa): o firmware de
# sw/example/neorv32_mnist_infer, compilado com SIM=1, roda uma inferencia sobre
# pesos e imagem que o modelo da SDRAM carrega no tempo 0, e os logits sao
# conferidos contra o expected.txt do modelo.
#
#   MODEL_DIR=<pasta> sim/run_infer_sim.sh [TILE] [MODO] [IMAGEM]
#     TILE    8 (padrao) ou 16
#     MODO    2 = acelerador com DMA (padrao), 1 = acelerador com a CPU movendo
#             os dados, 0 = so CPU (muito lento na simulacao)
#     IMAGEM  nome em MODEL_DIR/images (padrao: img_00_tshirt.bin)
#   MODEL_DIR  pasta com weights.bin, model_meta.h, images/ e expected.txt (a
#              saida do inference_tcc, ex.: .../inference_tcc/out/fashion_mnist).
#              O model_meta.h tem de ser o mesmo do firmware.
#
# Uma inferencia com DMA leva da ordem de 30 milhoes de ciclos: na faixa de 30 a
# 60 minutos no GHDL. SIM_TAG escolhe outra pasta de trabalho (rodar em paralelo).
set -e

cd "$(dirname "$0")/.."

TILE="${1:-8}"
MODE="${2:-2}"
IMAGE="${3:-img_00_tshirt.bin}"
GHDL="${GHDL:-ghdl}"
APP_DIR="sw/example/neorv32_mnist_infer"
TAG="${SIM_TAG:-infer_t${TILE}_m${MODE}}"
WORK="sim/build/${TAG}"
MAX_MS="${MAX_MS:-4000}"

if [ -z "${MODEL_DIR}" ] || [ ! -f "${MODEL_DIR}/weights.bin" ]; then
  echo "defina MODEL_DIR com a pasta do modelo (weights.bin, images/, expected.txt)"
  exit 2
fi
if ! cmp -s "${MODEL_DIR}/model_meta.h" "${APP_DIR}/model_meta.h"; then
  echo "${MODEL_DIR}/model_meta.h difere de ${APP_DIR}/model_meta.h: pesos de outro modelo"
  exit 2
fi
# O GHDL no Windows quer caminhos C:/..., nao /c/...
winpath() { if command -v cygpath > /dev/null; then cygpath -m "$1"; else echo "$1"; fi; }
WEIGHTS="$(winpath "${MODEL_DIR}/weights.bin")"
IMGFILE="$(winpath "${MODEL_DIR}/images/${IMAGE}")"

echo "=== Firmware: ${APP_DIR} (TILE=${TILE}, SIM_MODE=${MODE}) ==="
make -C "${APP_DIR}" clean > /dev/null
mkdir -p "${APP_DIR}/build"
make -C "${APP_DIR}" TILE="${TILE}" SIM=1 SIM_MODE="${MODE}" image

echo "=== Analisando o RTL em ${WORK} ==="
rm -rf "${WORK}"
mkdir -p "${WORK}"
# O GHDL mcode rele os fontes no -r: a imagem da IMEM vai para a pasta de trabalho,
# para o firmware poder ser recompilado (outra rodada em paralelo) sem afetar esta.
cp "${APP_DIR}/neorv32_imem_image.vhd" "${WORK}/neorv32_imem_image.vhd"
FILES=$(sed -e 's|NEORV32_RTL_PATH_PLACEHOLDER|rtl|' rtl/file_list_soc.f \
        | sed -e "s|rtl/core/neorv32_imem_image.vhd|${WORK}/neorv32_imem_image.vhd|")
FILES="${FILES}
rtl/core/neorv32_systolic_pe.vhd
rtl/core/neorv32_systolic_array.vhd
rtl/core/neorv32_systolic_wb_accelerator.vhd
rtl/core/neorv32_xbus_wb_gateway.vhd
rtl/core/neorv32_sdram_controller.vhd
sim/sdram_clk_pll_core_sim.vhd
rtl/core/neorv32_de2115_mnist_top.vhd
sim/neorv32_sdram_model.vhd
sim/sim_uart_rx.vhd
sim/neorv32_de2115_soc_tb.vhd"
G="--std=08 --workdir=${WORK} --work=neorv32"
for f in ${FILES}; do
  "${GHDL}" -a ${G} "${f}"
done
"${GHDL}" -e ${G} neorv32_de2115_soc_tb

echo "=== Rodando: ${IMAGE}, tile ${TILE}x${TILE}, modo ${MODE} ==="
LOG="sim/build/${TAG}.log"
# SDRAM_OFF_INPUT = 0x00100000 (sdram.h); 11 bits de linha cobrem 8 MB do banco 0
"${GHDL}" -r ${G} neorv32_de2115_soc_tb -gT="${TILE}" -gMAX_MS="${MAX_MS}" \
  -gUART_LOG="sim/build/${TAG}_uart0" -gSDRAM_ROW_BITS=11 \
  -gSDRAM_INIT0="${WEIGHTS}" -gSDRAM_OFFS0=0 \
  -gSDRAM_INIT1="${IMGFILE}" -gSDRAM_OFFS1=1048576 \
  --ieee-asserts=disable --max-stack-alloc=0 > "${LOG}" 2>&1 || true

grep -E '^\[|>>>|===' "${LOG}" | grep -v '\[tb\]' || true

EXPECTED=$(grep "^${IMAGE}" "${MODEL_DIR}/expected.txt" | sed -e 's/.*logits: *//' | tr -s ' ' | sed -e 's/ *$//')
GOT=$(grep -E '^\[logits(-cpu|-sw)?\]' "${LOG}" | head -1 | sed -e 's/^\[[^]]*\] *//' | tr -s ' ' | sed -e 's/ *$//')
echo "esperado: ${EXPECTED}"
echo "obtido:   ${GOT}"
if grep -q "firmware reportou PASS" "${LOG}" && [ -n "${EXPECTED}" ] && [ "${EXPECTED}" = "${GOT}" ]; then
  echo "PASS: logits identicos ao expected.txt"
else
  echo "FAIL: ver ${LOG}"
  exit 1
fi
