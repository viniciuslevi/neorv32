#!/usr/bin/env bash
# Testbenches unitarias do projeto do TCC no GHDL (sem CPU, rapidas):
#   neorv32_systolic_wb_accelerator_tb  T=8 e T=16 (registradores, matmul, IRQ)
#   neorv32_systolic_matmul_tb          matmul 8x8x8 com valores conhecidos
#   neorv32_sdram_controller_tb         escrita/leitura, refresh e mestre com
#                                       stb de 1 ciclo (estilo XBUS)
# A simulacao do SoC inteiro, com firmware, fica em sim/tcc/run_soc_sim.sh.
#
# GHDL: variavel GHDL, ou ghdl no PATH (testado com o GHDL 6.0.0 mcode).
set -e

cd "$(dirname "$0")/../.."

GHDL="${GHDL:-ghdl}"
WORK="sim/build/unit"
G="--std=08 --workdir=${WORK} --work=neorv32"

rm -rf "${WORK}"
mkdir -p "${WORK}"

echo "=== Analisando ==="
for f in \
  rtl/core/neorv32_package.vhd \
  rtl/tcc/tcc_systolic_pe.vhd \
  rtl/tcc/tcc_systolic_array.vhd \
  rtl/tcc/tcc_systolic_wb_accelerator.vhd \
  rtl/tcc/tcc_sdram_controller.vhd \
  sim/tcc/tcc_sdram_model.vhd \
  sim/tcc/tcc_systolic_wb_accelerator_tb.vhd \
  sim/tcc/tcc_systolic_matmul_tb.vhd \
  sim/tcc/tcc_sdram_controller_tb.vhd; do
  "${GHDL}" -a ${G} "${f}"
done

LOG="sim/build/unit.log"
: > "${LOG}"
run() {
  local tb="$1"; shift
  echo "=== ${tb} $* ==="
  "${GHDL}" -e ${G} "${tb}"
  "${GHDL}" -r ${G} "${tb}" "$@" --ieee-asserts=disable 2>&1 | tee -a "${LOG}" | grep -E '===|error'
}

run neorv32_systolic_wb_accelerator_tb -gT=8
run neorv32_systolic_wb_accelerator_tb -gT=16
run neorv32_systolic_matmul_tb
run neorv32_sdram_controller_tb

if grep -qE 'FAIL|error' "${LOG}"; then
  echo "FAIL: ver ${LOG}"
  exit 1
fi
echo "PASS (4 de 4)"
