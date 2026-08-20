MARCH = rv32i_zicsr_zifencei

# NOTE: for GHDL simulation (sim/run_accel_sim.sh), rebuild with:
#   make USER_FLAGS+="-DUART0_SIM_MODE"
# Do not enable it for real hardware -- it redirects all UART0 TX to the
# simulator's text.io output instead of the real UART0 transmitter pins.
USER_FLAGS += -Wl,--defsym,__neorv32_rom_size=32k
USER_FLAGS += -Wl,--defsym=__neorv32_ram_size=8k

NEORV32_HOME ?= ../../..

include $(NEORV32_HOME)/sw/common/common.mk
