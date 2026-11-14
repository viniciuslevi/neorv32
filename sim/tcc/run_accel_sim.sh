#!/usr/bin/env bash
set -e

cd "$(dirname "$0")/../.."

GHDL="${GHDL:-ghdl}"
ACCEL_TB="${1:-tcc_systolic_wb_accelerator_tb}"

mkdir -p sim/build

echo "=== Importing VHDL sources ==="
find rtl/core sim -type f -name '*.vhd' -exec \
  $GHDL -i --std=08 --workdir=sim/build --ieee=standard --work=neorv32 {} \;

echo "=== Analyzing $ACCEL_TB ==="
$GHDL -m --work=neorv32 --workdir=sim/build --std=08 "$ACCEL_TB"

echo "=== Running simulation ==="
$GHDL -r --work=neorv32 --workdir=sim/build --std=08 "$ACCEL_TB" \
  --max-stack-alloc=0 \
  --ieee-asserts=disable \
  --assert-level=error \
  --stop-time=5ms 2>&1 | tee sim/ghdl_accel.log

echo "=== Done ==="
if grep -q "ALL TESTS PASSED" sim/ghdl_accel.log; then
  echo "PASS"
else
  echo "CHECK LOG: sim/ghdl_accel.log"
fi
