# NEORV32 + acelerador sistólico INT8 na DE2-115 (TCC)

Este repositório é um *fork* do [NEORV32](https://github.com/stnolting/neorv32), de
Stephan Nolting, usado no Trabalho de Conclusão de Curso **"Aceleração de Redes
Neurais em FPGA Cyclone IV E"** (Vinícius Levi dos Santos, Engenharia da Computação,
UNIVASF, 2026). O trabalho integra ao processador RISC-V NEORV32 um acelerador
sistólico 8×8 INT8, um controlador de SDRAM e um *firmware* que executa a inferência
de uma rede convolucional (MNIST e Fashion-MNIST) na placa Terasic DE2-115.

O código do TCC fica no ramo `systolic-array-accelerator`, sobre o NEORV32
v1.12.8 (commit `a8d203db`). Tudo o que é do trabalho está em pastas `tcc/`; o
restante do repositório é o NEORV32 original, com as poucas alterações listadas
no fim deste arquivo.

## O que é do TCC

| Pasta | Conteúdo |
| --- | --- |
| `rtl/tcc/` | Hardware: elemento de processamento (`tcc_systolic_pe.vhd`), matriz sistólica (`tcc_systolic_array.vhd`), acelerador com interface Wishbone (`tcc_systolic_wb_accelerator.vhd`), controlador de SDRAM (`tcc_sdram_controller.vhd`), ponte XBUS→Wishbone (`tcc_xbus_wb_gateway.vhd`) e top-level da DE2-115 (`tcc_de2115_mnist_top.vhd`) |
| `rtl/tcc/ip/` | PLL do *clock* da SDRAM (`sdram_clk_pll_core`, gerado pelo ALTPLL do Quartus) |
| `rtl/tcc/quartus/` | Projeto Quartus do SoC completo (`tcc_mnist_accel.qpf/.qsf/.sdc`) |
| `rtl/tcc/legacy/` | Versões anteriores, fora do projeto final: acelerador como CFS (`neorv32_systolic_accelator.vhd`), `neorv32_systolic_top.vhd` e o teste isolado da matriz na placa (`neorv32_systolic_standalone_test.vhd`, projeto `kai.qpf`) |
| `sim/tcc/` | Testbenches, modelo de SDRAM e scripts de simulação no GHDL (ver `sim/tcc/README.md`) |
| `sw/tcc/mnist_infer/` | *Firmware* de inferência: carga de pesos e imagem pela UART, camadas da CNN, *driver* do acelerador, tratador de falhas da SDRAM, LCD |
| `sw/tcc/test_systolic_accel/` | Teste do acelerador na placa (`ALL TESTS PASSED`) |
| `sw/tcc/tools/` | `uart_upload.py`: envio do executável ao *bootloader* pelo Windows |
| `docs/tcc/` | Diário de bring-up, registro de depuração, guia de execução e notas de planejamento |

Os **arquivos** e as **entidades** VHDL do TCC têm o prefixo `tcc_` (por exemplo,
`tcc_systolic_pe.vhd` declara `tcc_systolic_pe`). As entidades são compiladas na
biblioteca `neorv32`, porque usam o `neorv32_package`. Nas versões usadas nas
medições do TCC, arquivos e entidades tinham o prefixo `neorv32_`; as versões
anteriores em `rtl/tcc/legacy/` mantêm os nomes originais.

O hardware e o *firmware* deste ramo são os das medições do TCC. O caminho de DMA
do acelerador, a correção do controlador de SDRAM e a simulação do SoC inteiro,
feitos depois das medições e testados só em simulação, estão no ramo
`tcc-dma-experimental`.

## Como usar

- **Síntese:** abrir `rtl/tcc/quartus/tcc_mnist_accel.qpf` no Quartus Prime 25.1
  (Lite ou Standard). O Quartus não cria o banco de dados dentro de pastas do
  OneDrive; compile numa cópia fora dele se for o caso.
- **Firmware:** `make -C sw/tcc/mnist_infer exe` (GCC xPack `riscv-none-elf-gcc`);
  envio com `make -C sw/tcc/mnist_infer upload_py UART_TTY=COMn`.
- **Simulação:** `sim/tcc/run_accel_sim.sh` (GHDL; ver `sim/tcc/README.md`).
- **Modelo e aplicativo:** os pesos (`weights.bin`, `model_meta.h`) vêm do
  repositório `inference_tcc`; a operação pela interface gráfica e a coleta em lote,
  do repositório `neorv32_infer_desktop`.

## Alterações em arquivos do NEORV32

| Arquivo | Alteração |
| --- | --- |
| `rtl/core/neorv32_bootrom_image.vhd` | Imagem do *bootloader* regenerada a partir de `sw/bootloader` (UART a 19.200 baud) com a alteração abaixo |
| `sw/bootloader/hal/source/uart.c` | Leitura bloqueante da UART no *bootloader* |
| `sw/image_gen/uart_upload.sh` | Envio em blocos com pausa e *timeout* maior, para adaptadores USB-serial que perdiam bytes |
| `rtl/test_setups/neorv32_test_setup_bootloader.vhd` | Frequência e modo de *boot* ajustados nos primeiros testes |
| `sw/example/demo_blink_led/makefile` | Caminho do compilador usado nos primeiros testes |
| `.gitignore` | Artefatos do Quartus e dos *builds* do TCC |
| `README.md` | Aviso no topo apontando para este arquivo |

Licença: BSD-3-Clause, a mesma do NEORV32.
