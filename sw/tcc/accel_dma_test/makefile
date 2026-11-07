# Teste do acelerador sistolico com DMA (Proposta A)
# Usa o driver do firmware de inferencia (../mnist_infer/accel_driver.c,
# via accel_driver_link.c).
# Requer o top-level tcc_de2115_mnist_top.vhd com IO_DMA_EN e o mesmo
# tamanho de array que ACCEL_TILE.
#
#   make TILE=8 exe          firmware para a placa (upload pelo bootloader)
#   make TILE=16 SIM=1 image imagem da IMEM para sim/tcc/run_soc_sim.sh

MARCH = rv32imc_zicsr_zifencei

TILE ?= 8
USER_FLAGS += -DACCEL_TILE=$(TILE)
USER_FLAGS += -Wl,--defsym,__neorv32_rom_size=32k
USER_FLAGS += -Wl,--defsym=__neorv32_ram_size=16k

# Na simulacao a UART0 escreve direto no console do simulador
ifeq ($(SIM),1)
USER_FLAGS += -DUART0_SIM_MODE
endif

# accel_driver_link.c inclui ../mnist_infer/accel_driver.c (ver o comentario la)
APP_INC = -I . -I ../mnist_infer

NEORV32_HOME ?= ../../..

include $(NEORV32_HOME)/sw/common/common.mk

# MinGW nao tem <elf.h>, exigido pelo image_gen: usa o cabecalho minimo do
# firmware de inferencia (so Windows)
ifeq ($(OS),Windows_NT)
CC_HOST += -I ../mnist_infer/tools/win_compat
endif
