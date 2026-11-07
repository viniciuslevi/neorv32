# NEORV32 MNIST Inference (Fase 3/4 do TCC)
# Requer o top-level tcc_de2115_mnist_top.vhd (rtl/core), com
# XBUS_EN=true, RISCV_ISA_M=true, RISCV_ISA_C=true, RISCV_ISA_Zicntr=true,
# IMEM_SIZE=32k, DMEM_SIZE=16k (ver generics do top-level).

MARCH = rv32imc_zicsr_zifencei

# Tamanho do array sistolico do bitstream (ACCEL_ARRAY_SIZE no top-level): 8 ou 16.
# O firmware confere contra o registrador INFO no boot.  make TILE=16 exe
TILE ?= 8
USER_FLAGS += -DACCEL_TILE=$(TILE)

# Simulacao do SoC (sim/tcc/run_infer_sim.sh): UART direto no console do simulador,
# pesos e imagem ja na SDRAM, uma inferencia no modo SIM_MODE (2 = DMA, 1 = CPU
# movendo os dados, 0 = so CPU). Ver sim_main() em main.c.
ifeq ($(SIM),1)
SIM_MODE ?= 2
USER_FLAGS += -DUART0_SIM_MODE -DSIM_PRELOADED -DSIM_INFER_MODE=$(SIM_MODE)
endif

USER_FLAGS += -Wl,--defsym,__neorv32_rom_size=32k
USER_FLAGS += -Wl,--defsym=__neorv32_ram_size=16k

NEORV32_HOME ?= ../../..

# No Windows a porta serial e COMn (ex.: make upload_py UART_TTY=COM5)
ifeq ($(OS),Windows_NT)
UART_TTY ?= COM17
endif

include $(NEORV32_HOME)/sw/common/common.mk

# MinGW nao tem <elf.h>, exigido pelo image_gen: usa um cabecalho minimo (so Windows)
ifeq ($(OS),Windows_NT)
CC_HOST += -I tools/win_compat
endif

# Upload via Python/pyserial (pip install pyserial). Alternativa ao "make upload",
# cujo uart_upload.sh depende de bash+stty e nao configura portas COM no Windows.
PYTHON ?= python

.PHONY: upload_py
upload_py: $(APP_EXE)
	$(Q)$(PYTHON) $(NEORV32_HOME)/sw/tcc/tools/uart_upload.py $(UART_TTY) $(APP_EXE)
