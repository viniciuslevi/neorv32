#!/usr/bin/env bash
# Simulacao do SoC da placa (tcc_de2115_mnist_top + modelo de SDRAM) no GHDL,
# rodando um firmware gravado na IMEM.
#
#   sim/tcc/run_soc_sim.sh [TILE] [APP]
#     TILE  tamanho do array sistolico, 8 (padrao) ou 16
#     APP   pasta do firmware em sw/example (padrao: accel_dma_test)
#
# Compila o firmware com UART0_SIM_MODE (o texto da UART sai no console) e
# ACCEL_TILE=TILE, gera a imagem da IMEM e roda sim/tcc/tcc_de2115_soc_tb.vhd,
# que termina quando o firmware escreve 0xA5 (PASS) ou 0xEE (FAIL) em LEDG.
# Troca dois arquivos do RTL: a imagem da IMEM pela do firmware, e o PLL da
# SDRAM (ALTPLL, so Quartus) pelo stub sim/tcc/sdram_clk_pll_core_sim.vhd.
#
# GHDL: variavel GHDL, ou ghdl no PATH (testado com o GHDL 6.0.0 mcode).
set -e

cd "$(dirname "$0")/../.."

TILE="${1:-8}"
APP="${2:-accel_dma_test}"
GHDL="${GHDL:-ghdl}"
TAG="${SIM_TAG:-soc_t${TILE}}"   # SIM_TAG: outro nome para rodar em paralelo
WORK="sim/build/${TAG}"
APP_DIR="sw/tcc/${APP}"
# SDRAM_CTRL: outro arquivo de controlador (ex.: uma versao antiga, para comparar)
SDRAM_CTRL="${SDRAM_CTRL:-rtl/tcc/tcc_sdram_controller.vhd}"

echo "=== Firmware: ${APP_DIR} (ACCEL_TILE=${TILE}, UART0_SIM_MODE) ==="
mkdir -p "${APP_DIR}/build"
make -C "${APP_DIR}" TILE="${TILE}" SIM=1 clean > /dev/null
mkdir -p "${APP_DIR}/build"
make -C "${APP_DIR}" TILE="${TILE}" SIM=1 image

echo "=== Analisando o RTL em ${WORK} ==="
rm -rf "${WORK}"
mkdir -p "${WORK}"
# O GHDL mcode rele os fontes no -r: a imagem da IMEM vai para a pasta de trabalho,
# para o firmware poder ser recompilado (outra rodada em paralelo) sem afetar esta.
cp "${APP_DIR}/neorv32_imem_image.vhd" "${WORK}/neorv32_imem_image.vhd"
FILES=$(sed -e 's|NEORV32_RTL_PATH_PLACEHOLDER|rtl|' rtl/file_list_soc.f \
        | sed -e "s|rtl/core/neorv32_imem_image.vhd|${WORK}/neorv32_imem_image.vhd|")
FILES="${FILES}
rtl/tcc/tcc_systolic_pe.vhd
rtl/tcc/tcc_systolic_array.vhd
rtl/tcc/tcc_systolic_wb_accelerator.vhd
rtl/tcc/tcc_xbus_wb_gateway.vhd
${SDRAM_CTRL}
sim/tcc/sdram_clk_pll_core_sim.vhd
rtl/tcc/tcc_de2115_mnist_top.vhd
sim/tcc/tcc_sdram_model.vhd
sim/sim_uart_rx.vhd
sim/tcc/tcc_de2115_soc_tb.vhd"
G="--std=08 --workdir=${WORK} --work=neorv32"
for f in ${FILES}; do
  "${GHDL}" -a ${G} "${f}"
done
"${GHDL}" -e ${G} tcc_de2115_soc_tb

echo "=== Rodando (tile ${TILE}x${TILE}) ==="
LOG="sim/build/${TAG}.log"
"${GHDL}" -r ${G} tcc_de2115_soc_tb -gT="${TILE}" -gUART_LOG="sim/build/${TAG}_uart0" \
  --ieee-asserts=disable --max-stack-alloc=0 2>&1 | tee "${LOG}"

if grep -q "firmware reportou PASS" "${LOG}"; then
  echo "PASS"
else
  echo "FAIL: ver ${LOG}"
  exit 1
fi
