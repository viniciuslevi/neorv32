# NEORV32 MNIST Inference (Fase 3/4 do TCC)
# Requer o top-level neorv32_de2115_mnist_top.vhd (rtl/core), com
# XBUS_EN=true, RISCV_ISA_M=true, RISCV_ISA_C=true, RISCV_ISA_Zicntr=true,
# IMEM_SIZE=32k, DMEM_SIZE=16k (ver generics do top-level).

MARCH = rv32imc_zicsr_zifencei

USER_FLAGS += -Wl,--defsym,__neorv32_rom_size=32k
USER_FLAGS += -Wl,--defsym=__neorv32_ram_size=16k

NEORV32_HOME ?= ../../..

include $(NEORV32_HOME)/sw/common/common.mk
