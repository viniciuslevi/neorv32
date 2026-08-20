# neorv32_mnist_infer — Fase 3/4 do TCC

Inferência MNIST end-to-end no NEORV32 + acelerador sistólico 8×8 INT8 + SDRAM,
na DE2-115 (Cyclone IV E). Implementa a Fase 3 ("Integração SDRAM + NEORV32") e a
Fase 4 ("Inferência end-to-end") da [Metodologia](../../../rtl/core/docs/) do TCC.

## O que foi feito nesta etapa

### RTL (`rtl/core/`)

| Arquivo | O que é |
|---|---|
| `neorv32_systolic_array.vhd` | **Corrigido**: array 8×8 agora carrega um tile de pesos completo (64 B) por PE, em vez de um vetor de 8 B broadcast por linha. Sem essa correção o hardware só realizava produto matriz×vetor, incapaz de multiplicar dois tiles 8×8 completos (necessário para qualquer camada conv/FC real). |
| `neorv32_systolic_wb_accelerator.vhd` | Wrapper Wishbone realinhado para o mapa de memória em janelas (`CTRL`/`STATUS`/`CONFIG` + janelas `WEIGHT`/`ACT`/`RESULT`) que o firmware já pressupunha (`sw/example/test_systolic_accel/main.c` foi escrito contra esse mapa antes de a RTL implementá-lo). |
| `neorv32_sdram_controller.vhd` | Controlador SDRAM próprio (Wishbone-classic, política *close-page*), para os 2× ISSI IS42S16320D da DE2-115. Substitui a IP do Quartus (MegaWizard/IP Catalog não disponível via linha de comando neste ambiente de desenvolvimento). |
| `neorv32_xbus_wb_gateway.vhd` | Decodificador de endereço: XBUS do NEORV32 → SDRAM (`0xA0000000`) ou acelerador (`0x90000000`). |
| `neorv32_de2115_mnist_top.vhd` | Top-level integrado: NEORV32 (RV32IMC) + gateway + SDRAM + acelerador, pinagem DE2-115. |
| `neorv32_mnist_accel.qsf`/`.qpf` | Projeto Quartus separado (convive com `kai.qsf` da Fase 1), pinos de SDRAM extraídos de `DE2_115_pin_assignments.xlsx` (Terasic). |

### Software (este diretório)

| Arquivo | Função |
|---|---|
| `accel_driver.c/h` | `accel_matmul_i8()`: multiplicação de matrizes INT8 genérica (M×K por K×N) via tiles 8×8, com padding automático de borda e correção de zero-point (quantização assimétrica). |
| `sdram.c/h` | Mapa de regiões da SDRAM + protocolo de carga via UART (`sdram_uart_handshake_loop`). |
| `inference.c/h` | Pipeline completo: `conv2d` (im2col + acelerador) → `maxpool2x2` → `conv2d` → `maxpool2x2` → `dense` → `dense` → argmax. Benchmark SW-vs-HW de um tile 8×8×8. |
| `model_meta.h` | Gerado por `ia_models/src/export_weights.py` a partir do `.tflite` real (não editar à mão). |
| `main.c` | Orquestra handshake UART, inferência, benchmark. |
| `tools/send_weights.py` | Ferramenta host: envia `weights.bin` + uma imagem MNIST de teste pela UART. |

### Python (`ia_models/src/export_weights.py`, Fase 2→3)

Lê o grafo do `mnist_int8_full.tflite` via `interpreter._get_ops_details()` (não
transcreve escalas/formas manualmente) e gera:
- `outputs/weights.bin` (422 344 B): pesos INT8 (reformatados para o layout `(K,N)`
  esperado pelo acelerador) + bias INT32, por camada.
- `outputs/model_meta.h`: offsets, dimensões e parâmetros de quantização reais.

## Mapa de memória

```
XBUS (CPU):
  0xA0000000 - 0xA7FFFFFF   SDRAM 128 MB
  0x90000000 - 0x9000FFFF   Acelerador sistólico

SDRAM (offsets relativos a 0xA0000000):
  0x000000   weights.bin (pesos + bias de todas as camadas)
  0x100000   imagem de entrada (784 B, 28x28 INT8)
  0x110000   buffer de ativações A (ping-pong, 256 KB)
  0x150000   buffer de ativações B (ping-pong, 256 KB)
  0x200000   scratch im2col (512 KB)
  0x300000   acumulador INT32 do matmul (512 KB)
```

## Como reproduzir

```bash
# 1. (Re)gerar weights.bin + model_meta.h a partir do modelo treinado
cd ~/Documentos/tcc/ia_models
source venv/bin/activate
python src/export_weights.py
cp outputs/model_meta.h ~/neorv32/sw/example/neorv32_mnist_infer/model_meta.h

# 2. Compilar o firmware
cd ~/neorv32/sw/example/neorv32_mnist_infer
export PATH="/opt/riscv-none-elf-gcc/bin:$PATH"
make clean elf exe    # gera neorv32_exe.bin para upload via bootloader

# 3. Sintetizar o hardware integrado (Quartus Prime 18.1, precisa de GUI/licença)
cd ~/neorv32/rtl/core
quartus_sh --flow compile neorv32_mnist_accel

# 4. Programar a DE2-115 e subir o firmware via bootloader NEORV32 (UART)
#    (ver sw/bootloader/ e a documentação padrão do NEORV32 para o fluxo de upload)

# 5. No PC, enviar pesos + imagem e rodar a inferência
python3 tools/send_weights.py --port /dev/ttyUSB1 \
    --weights ~/Documentos/tcc/ia_models/outputs/weights.bin \
    --mnist-index 0
```

## O que está validado e o que não está

- **Compilação do firmware**: ✅ testada com `riscv-none-elf-gcc` (10 416 B `.text`,
  cabe folgado nos 32 KB de ROM configurados).
- **Geração de `weights.bin`/`model_meta.h`**: ✅ testada de ponta a ponta contra o
  modelo real treinado (`ia_models/outputs/mnist_int8_full.tflite`).
- **Matemática do acelerador (`RESULT = ACT @ WEIGHT`)**: verificada por simulação
  em Python (modelo ciclo-a-ciclo do PE/array) durante o desenvolvimento — confirma
  que a correção da RTL (tile de pesos completo) produz matmul correto.
- **Síntese Quartus**: ✅ executada de verdade contra o EP4CE115F29C7 (Quartus Prime
  18.1 local, `~/intelFPGA_lite/18.1`) — 0 erros, `.sof` gerado, timing fecha a 50 MHz
  com folga (Fmax 66,71–72,64 MHz conforme corner). Ver `../../../rtl/core/output_files_mnist_accel/`.
- **Simulação VHDL (GHDL 1.0.0)**: ✅ **executada de ponta a ponta, PASS nas duas
  testbenches**. Esse processo encontrou e corrigiu dois bugs funcionais reais que a
  síntese sozinha não detecta (ela não verifica comportamento, só estrutura):
  1. Condição de corrida no `array_done` (`neorv32_systolic_wb_accelerator.vhd`,
     estado `S_COMPUTE`): no ciclo exato em que uma nova linha do tile começava, o
     `done` da linha anterior ainda estava em `'1'`, fazendo a FSM capturar o
     resultado após 1-2 ciclos em vez dos 15 necessários. Corrompia 7 das 8 linhas
     de qualquer tile (só a linha 0, sem resíduo de chamada anterior, sempre batia).
  2. Timing de leitura do controlador SDRAM (`neorv32_sdram_controller.vhd`): o
     estado `S_READ_CAPTURE` amostrava `dram_dq_io` um ciclo depois que o dado já
     tinha voltado a alta impedância (o chip só mantém o dado válido por 1 ciclo,
     burst length=1). Corrigido capturando dentro do próprio `S_READ_WAIT`.

  Resultados:
  - `sim/neorv32_systolic_matmul_tb.vhd`: **64/64 resultados corretos** (matmul
    8×8×8 completo, autoverificável contra referência calculada em VHDL).
  - `sim/neorv32_sdram_controller_tb.vhd` + `sim/neorv32_sdram_model.vhd`:
    **escrita/leitura íntegra** em bancos e linhas distintos (força ACTIVE/PRECHARGE
    reais), inclusive através de um ciclo de refresh automático no meio do teste.

  Para reproduzir:
  ```bash
  ghdl -a --std=08 --work=neorv32 rtl/core/neorv32_package.vhd
  ghdl -a --std=08 -P. rtl/core/neorv32_systolic_pe.vhd rtl/core/neorv32_systolic_array.vhd \
      rtl/core/neorv32_systolic_wb_accelerator.vhd sim/neorv32_systolic_matmul_tb.vhd
  ghdl -e --std=08 -P. neorv32_systolic_matmul_tb && ghdl -r --std=08 -P. neorv32_systolic_matmul_tb

  ghdl -a --std=08 -P. rtl/core/neorv32_sdram_controller.vhd sim/neorv32_sdram_model.vhd \
      sim/neorv32_sdram_controller_tb.vhd
  ghdl -e --std=08 -P. neorv32_sdram_controller_tb && ghdl -r --std=08 -P. neorv32_sdram_controller_tb
  ```
- **Inferência real na DE2-115**: **pendente** — requer bancada com a placa física
  e programação via USB-Blaster do `.sof` já gerado. É o único passo que falta para
  fechar a Fase 4 e coletar os números (acurácia, ciclos, GOPS) do Capítulo 5 — a
  lógica de cálculo já está validada em simulação, e o hardware já está sintetizado.

## Limitações conhecidas (documentar no TCC, Cap. 3.11)

- Controlador SDRAM usa política *close-page* (ACTIVE→READ/WRITE→PRECHARGE a cada
  acesso) — simples e correta, mas não otimizada para throughput. Otimização para
  *open-page* fica como trabalho futuro.
- `accel_matmul_i8` usa apenas 1 tile de ativação por chamada nas camadas densas
  (M=1) — usa 1/8 da capacidade de paralelismo do array nessas camadas. Processar
  em lote (múltiplas imagens) aproveitaria melhor o hardware.
- Requantização usa `float` (soft-float via libgcc) em vez de multiplicação de
  ponto fixo inteiro (como o TFLite faz internamente) — mais simples de auditar,
  porém mais lenta. Otimização possível para trabalho futuro.
- Sem DMA: a CPU intermedeia toda cópia SDRAM↔acelerador (aceito no escopo do
  TCC, ver Metodologia 3.11).
