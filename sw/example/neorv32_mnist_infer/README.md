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
| `neorv32_sdram_controller.vhd` | Controlador SDRAM próprio (Wishbone-classic, política *close-page*), para os 2× ISSI IS42S16320D da DE2-115. Substitui a IP do Quartus (MegaWizard/IP Catalog não disponível via linha de comando neste ambiente de desenvolvimento). Inclui agora um estado `S_WRITE_RECOVER` para respeitar tWR (write recovery) entre o comando WRITE e o PRECHARGE seguinte, que faltava por completo na versão original. |
| `neorv32_xbus_wb_gateway.vhd` | Decodificador de endereço: XBUS do NEORV32 → SDRAM (`0xA0000000`) ou acelerador (`0x90000000`). |
| `neorv32_de2115_mnist_top.vhd` | Top-level integrado: NEORV32 (RV32IMC) + gateway + SDRAM + acelerador, pinagem DE2-115. `DRAM_CLK` agora vem de um PLL dedicado (`sdram_clk_pll_core`) com defasagem de -2 ns em vez de um inversor combinacional puro (`not clk_i`); o reset do controlador SDRAM fica retido até o PLL travar (`locked`). |
| `sdram_clk_pll_core.vhd`/`.qip` | PLL (ALTPLL) para `DRAM_CLK`, gerado via `qmegawiz -silent` (linha de comando, sem MegaWizard/IP Catalog — ver seção "Bring-up em hardware real" abaixo). |
| `neorv32_mnist_accel.qsf`/`.qpf` | Projeto Quartus separado (convive com `kai.qsf` da Fase 1), pinos de SDRAM extraídos de `DE2_115_pin_assignments.xlsx` (Terasic). |

### Software (este diretório)

| Arquivo | Função |
|---|---|
| `accel_driver.c/h` | `accel_matmul_i8()`: multiplicação de matrizes INT8 genérica (M×K por K×N) via tiles 8×8, com padding automático de borda e correção de zero-point (quantização assimétrica). |
| `sdram.c/h` | Mapa de regiões da SDRAM + protocolo de carga via UART (`sdram_uart_handshake_loop`). O `'R'` (ready) é reenviado periodicamente (poll de 1ms) em vez de mandado uma única vez, e `sdram_uart_recv_blob` recebe em pedaços de 64B confirmados individualmente (`'K'`/`'N'` + retry pelo host) em vez de uma leitura cega do blob inteiro. Também instala (`sdram_install_fault_retry_handler`) um handler de exceção que reexecuta automaticamente qualquer Load/Store access fault na SDRAM em vez de deixar o RTE pular a instrução (ver "Bring-up em hardware real"). |
| `inference.c/h` | Pipeline completo: `conv2d` (im2col + acelerador) → `maxpool2x2` → `conv2d` → `maxpool2x2` → `dense` → `dense` → argmax. Benchmark SW-vs-HW de um tile 8×8×8. |
| `model_meta.h` | Gerado por `ia_models/src/export_weights.py` a partir do `.tflite` real (não editar à mão). |
| `main.c` | Orquestra handshake UART, inferência, benchmark. Instala `neorv32_rte_setup()` (handlers de debug de exceção) e `sdram_install_fault_retry_handler()` logo no início. |
| `tools/send_weights.py` | Ferramenta host: envia `weights.bin` + uma imagem MNIST de teste pela UART, em pedaços de 64B confirmados (mesmo protocolo do `sdram.c`), com retry automático por pedaço. |

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
#    Linux:   make upload UART_TTY=/dev/ttyUSB1
#    Windows: pip install pyserial && make upload_py UART_TTY=COM17
#             (uart_upload.sh não funciona no Windows: o stty do MSYS/Git Bash não
#              configura portas COM; upload_py usa sw/image_gen/uart_upload.py)
#    Resete o processador antes de rodar o upload.

# 5. No PC, enviar pesos + imagem e rodar a inferência
#    A aplicação escuta a 115200 (o bootloader continua a 19200).
python3 tools/send_weights.py --port /dev/ttyUSB1 --baud 115200 \
    --weights caminho/para/weights.bin \
    --image caminho/para/imagem.bin
#    Próximas imagens: KEY1 na placa, depois só --image (os pesos ficam na SDRAM).
```

Passo a passo completo, com armadilhas: `rtl/core/docs/Guia de Execucao.md`.

## O que está validado e o que não está

- **Compilação do firmware**: ✅ testada com `riscv-none-elf-gcc` (~13 KB `.text` com
  os handlers de debug/retry de exceção instalados, cabe folgado nos 32 KB de ROM
  configurados).
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
- **Inferência real na DE2-115**: ✅ **executada de ponta a ponta** — handshake UART,
  carga de `weights.bin` (422 344 B) + imagem de teste, todas as camadas da CNN, e
  argmax final rodaram na placa física. Ver "Bring-up em hardware real" abaixo para
  a jornada de depuração (SDRAM não funcionava de primeira) e "Limitações conhecidas"
  para os dois problemas ainda abertos (classe prevista errada; divergência SW/HW no
  benchmark).

## Bring-up em hardware real

A integração SDRAM + NEORV32 exigiu bem mais depuração em hardware real do que a
simulação (com modelo ideal de SDRAM) conseguia prever. Resumo das causas encontradas,
na ordem em que apareceram:

1. **UART instável (upload do bootloader e do `send_weights.py`)**: o adaptador
   USB-serial (CH340) derruba bytes sob rajada contínua em baud baixo. Corrigido
   enviando em pedaços pequenos com confirmação por pedaço (`sw/image_gen/uart_upload.sh`,
   `tools/send_weights.py`) em vez de uma rajada cega do arquivo inteiro.
2. **`DRAM_CLK` sem PLL**: a versão original gerava `DRAM_CLK` com um inversor
   combinacional puro (`not clk_i`) alimentando o pino direto — sem um PLL/rede de
   clock dedicada, a fase real na placa fica sujeita ao atraso de roteamento genérico
   do FPGA, que a simulação (SDRAM ideal, sem esse atraso) não captura. Corrigido com
   um PLL (ALTPLL) dedicado, com defasagem de -2 ns. Como a GUI do Quartus (IP
   Catalog/MegaWizard) travava neste ambiente, o PLL foi gerado via linha de comando
   (`qmegawiz -silent`, ver comando abaixo) — o wizard interativo depende de
   bibliotecas (`libpng12`, `libccl_*`, `libQtCore.so.4` etc.) que só existem dentro
   da própria instalação do Quartus (`$QUARTUS_ROOTDIR/linux64`), não no sistema;
   basta apontar `LD_LIBRARY_PATH` para lá.
3. **tWR ausente**: o controlador nunca esperava o tempo de *write recovery* (tWR)
   entre o comando WRITE e o PRECHARGE seguinte — só tRP/tRCD/tRC/tMRD eram
   respeitados. Corrigido com um novo estado `S_WRITE_RECOVER`.
4. **Access faults intermitentes** (causa raiz ainda não isolada): mesmo com o PLL e
   o tWR corrigidos, escritas/leituras isoladas na SDRAM ainda falham
   esporadicamente — confirmado via `neorv32_rte_setup()` como `Store access fault`/
   `Load access fault` reais (o XBUS_TIMEOUT do NEORV32 funcionando como projetado,
   detectando o controlador não confirmar (`ack`) dentro de 2048 ciclos), não um
   travamento infinito da FSM como parecia antes de instalar os handlers de debug.
   O padrão apontava para os bancos/linhas mais tardios de uma sequência de acessos,
   consistente com uma condição de corrida rara envolvendo o timer de refresh
   automático, mas a causa exata não foi isolada dentro do tempo desta sessão.
   **Mitigação aplicada** (`sdram_install_fault_retry_handler` em `sdram.c`): em vez
   de deixar o handler padrão do RTE pular a instrução que falhou (perdendo o dado),
   um handler customizado recua `MEPC` para forçar a mesma instrução a executar de
   novo, com um limite de tentativas consecutivas para não travar de verdade se a
   falha for persistente. Na prática, os poucos access faults observados por execução
   sempre sucedem já na primeira ou segunda tentativa.

Comando usado para gerar o PLL sem GUI (ajustar `QUARTUS_ROOTDIR` para sua instalação):
```bash
export QUARTUS_ROOTDIR=~/intelFPGA_lite/18.1/quartus
export PATH="$QUARTUS_ROOTDIR/linux64:$QUARTUS_ROOTDIR/bin:$PATH"
export LD_LIBRARY_PATH="$QUARTUS_ROOTDIR/linux64:$QUARTUS_ROOTDIR/../lib/usr/lib/x86_64-linux-gnu:$LD_LIBRARY_PATH"
qmegawiz -silent module=altpll intended_device_family="Cyclone IV E" operation_mode=NORMAL \
  pll_type=AUTO inclk0_input_frequency=20000 clk0_divide_by=1 clk0_multiply_by=1 \
  clk0_duty_cycle=50 clk0_phase_shift="-3000" compensate_clock=CLK0 \
  self_reset_on_loss_lock=OFF width_clock=5 \
  port_activeclock=PORT_UNUSED port_areset=PORT_UNUSED port_clkbad0=PORT_UNUSED \
  port_clkbad1=PORT_UNUSED port_clkloss=PORT_UNUSED port_clkswitch=PORT_UNUSED \
  port_configupdate=PORT_UNUSED port_fbin=PORT_UNUSED port_inclk1=PORT_UNUSED \
  port_pfdena=PORT_UNUSED port_phasecounterselect=PORT_UNUSED port_phasedone=PORT_UNUSED \
  port_phasestep=PORT_UNUSED port_phaseupdown=PORT_UNUSED port_pllena=PORT_UNUSED \
  port_scanaclr=PORT_UNUSED port_scanclk=PORT_UNUSED port_scanclkena=PORT_UNUSED \
  port_scandata=PORT_UNUSED port_scandataout=PORT_UNUSED port_scandone=PORT_UNUSED \
  port_scanread=PORT_UNUSED port_scanwrite=PORT_UNUSED port_clk1=PORT_UNUSED \
  port_clk2=PORT_UNUSED port_clk3=PORT_UNUSED port_clk4=PORT_UNUSED \
  sdram_clk_pll_core.vhd  # a extensao .vhd no nome de saida e obrigatoria
```
Note que o `qmegawiz` também gera um `.qip` — ele precisa ser adicionado ao projeto
via `set_global_assignment -name QIP_FILE sdram_clk_pll_core.qip` no `.qsf` (não
`VHDL_FILE`), senão o Quartus não elabora os parâmetros internos do PLL corretamente.

## Endereço não registrado no controlador SDRAM (bug de raiz, corrigido)

Bug encontrado depois do primeiro bring-up, responsável por corrupção sistemática
da SDRAM — e provável causa da classe prevista incorreta.

**O defeito.** Em `neorv32_sdram_controller.vhd`, o processo `latch_req` registrava
`req_wdata`, `req_sel` e `req_we` no instante em que a requisição Wishbone era
aceita, mas o endereço não: `req_addr` vinha de uma atribuição concorrente,
`req_addr <= wb_adr_i(26 downto 2)`, e portanto acompanhava `wb_adr_i`
combinacionalmente durante toda a FSM. Como a máquina leva vários ciclos entre
ACTIVE e READ/WRITE (espera de tRCD, depois PRECHARGE), qualquer mudança em
`wb_adr_i` nesse intervalo fazia o comando ACTIVE capturar a linha de um endereço
e o READ/WRITE capturar a coluna de outro. Resultado: dados gravados e lidos na
palavra vizinha.

**Correção.** Registrar `req_addr` junto com o restante da requisição, no mesmo
ciclo, dentro de `latch_req`.

**Por que a simulação não pegou.** `sim/neorv32_sdram_controller_tb.vhd` passa nos
dois testes. A testbench mantém `wb_adr_i` estável durante toda a transação — é o
que uma testbench escrita à mão naturalmente faz. O mestre Wishbone real, não. O
defeito estava exatamente na interface com o mestre real, fora do que o modelo
idealizado exercitava. Esse é o achado metodológico mais relevante do episódio.

**Por que o smoke test original não bastou.** O teste de 16 bytes de `main.c`
detectava *que* havia erro, mas não *qual*. Foi preciso um diagnóstico melhor
(`sdram_diag.c`) para localizar a causa. O ponto central: **padrões uniformes são
cegos a erro de endereçamento**. Escrevendo `0xAAAAAAAA` em toda parte, ler do
endereço errado devolve o valor certo, e o teste passa. Só valores únicos por
palavra revelam o problema — no teste com `0x00000000`, `0xFFFFFFFF`, `0xAAAAAAAA`
e `0x55555555` o resultado era 0 erros, enquanto o padrão endereço-como-dado dava
256/256 palavras erradas.

Uma armadilha adicional, vivida durante a investigação: gravar `TAG + i` faz
palavras vizinhas diferirem num único bit, e aí "leu o endereço errado" e "leu o
bit 0 corrompido" produzem exatamente a mesma evidência. Trocar o valor para
`TAG + i*0x55` separa os dois casos — o valor lido ou é múltiplo válido de `0x55`
(endereço) ou não é (dado).

**Resultado medido** (DE2-115, quatro offsets em bancos/linhas distintos, 256
palavras de 32 bits por padrão):

| | antes | depois |
|---|---|---|
| Padrões uniformes | 0 erros | 0 erros |
| Padrão endereço-como-dado | 1024 erros | 153–159 |
| Erros classificados como endereço | 100% | **0** |
| Bits afetados (teste A) | 2,3,4,5,6,7,8,9 | só o 3 |

**Segundo defeito: DRAM_CLK nunca veio do PLL.** O commit 27b6f5f3 descreve ter
substituído o inversor combinacional por um PLL defasado, mas no código a saída
`c0` ficou em `open` e `dram_clk_o <= not clk_i` permaneceu, marcado como
"DIAGNOSTICO TEMPORARIO". O PLL existia apenas para o sinal `locked`. Ou seja, a
fase configurada no `sdram_clk_pll_core` nunca esteve em vigor, e o clock que o
chip recebia saía de lógica combinacional roteada genericamente até o pino --
exatamente a condição que a correção pretendia eliminar.

Corrigido conectando `c0` a `dram_clk_o`, com defasagem de 180° (`-10000` ps).
São 180° porque é a relação que a FSM do controlador pressupõe: ela troca
endereço/comando na borda de `clk_i` e espera que o chip amostre meio ciclo
depois. É a mesma fase do `not clk_i` original, mas agora através da rede de
clock dedicada do PLL em vez de roteamento genérico.

**O SDC da interface SDRAM.** A versão anterior de `neorv32_mnist_accel.sdc`
tinha quatro linhas e restringia apenas `clk_i`. O Timing Analyzer reportava
5,49 ns de folga -- cobrindo só a lógica interna. O caminho FPGA↔chip nunca foi
analisado, e o fitter roteava os pinos de dado e endereço sem meta de timing.
Com o SDC completo (`create_generated_clock` para o pino DRAM_CLK,
`set_output_delay`/`set_input_delay` nos pinos de dado, endereço, comando e
máscara), a mesma compilação passou a acusar **-2,884 ns no caminho de leitura**
`dram_dq_io[*] -> clk_i`. O relatório antigo dava uma garantia que não cobria a
interface onde estava o problema.

**Limite do método: a análise de timing sozinha escolheu errado.** Com o SDC no
lugar, uma varredura de fase indicou 0 ps como ótimo (folga de +4,13 ns na
leitura e +7,11 ns na escrita). Em hardware, 0 ps produziu deslocamento de
endereço de exatamente uma palavra em 100% dos acessos -- o mapa de bits do
teste A virou a sequência 1024, 512, 256, 128, 64, 32, 16, 8, assinatura de
soma de 4 bytes com propagação de vai-um. A razão: com fase 0 o chip amostra na
mesma borda em que o FPGA troca o barramento, e o TimeQuest resolve isso
escolhendo a borda de captura seguinte (janela de 20 ns, folga aparente enorme),
relação que não é a que a FSM implementa. Para o SDC refletir o projeto de fato
seria preciso declarar, com `set_multicycle_path`, em que ciclo cada comando
deve ser capturado. Registrado aqui porque é um resultado metodológico: o SDC
tornou o problema *visível e quantificável*, mas o valor final só foi validado
em hardware.

**Resultado final** (DE2-115, quatro offsets, 256 palavras de 32 bits por padrão,
incluindo o padrão endereço-como-dado que nunca havia passado):

```
-- A) TOTAL: 0 palavras com erro em 5120
-- B) DQ[15:0] = 0 erros | DQ[31:16] = 0 erros
-- E) 0/256 erradas | ENDERECO=0 DADO=0 | faults wr=0 rd=0
-- F) 0/256 erradas na conferencia imediata
===== FIM (PASS) =====
```

**Ainda em aberto.** O contador acusa 142 access faults retentados com 0 erros de
dado. São falhas transitórias de ack dentro do `XBUS_TIMEOUT` -- o mesmo sintoma
que 27b6f5f3 descreveu sem isolar. Os dados saem corretos porque
`sdram_install_fault_retry_handler` reexecuta a instrução, mas isso é o retry
funcionando, não a ausência de falha. Os parâmetros do IS42S16320D usados no SDC
(`tSU` 1,5 ns, `tHD` 0,8 ns, `tAC` 5,4 ns, `tOH` 2,7 ns) ainda precisam ser
conferidos no datasheet, e os atrasos de trilha da placa são estimativas.

## Interface do acelerador: start sem borda e done por linha (corrigido)

Dois defeitos independentes na interface que o software enxerga, ambos tornando
o acelerador inutil na pratica depois da primeira operacao.

**A -- o start nunca gerava borda.** A FSM do wrapper dispara na borda de subida
de `CTRL[0]`, nao no nivel:

```vhdl
start_req := ctrl_reg(0) and (not prev_ctrl_start) and (not array_busy) and (not array_clear);
```

O driver escrevia `ACCEL_CTRL = 0x1` e nunca voltava a zero. Logo, so a primeira
operacao apos o reset produzia borda; da segunda em diante o array nao iniciava.
E como `done` continuava setado da vez anterior, o polling saia de imediato e o
driver lia o resultado do tile ANTERIOR. A inferencia inteira usava o primeiro
tile repetido.

**B -- `STATUS.done` era por linha, nao por operacao.** O wrapper roda o array 8
vezes (uma por linha do tile 8x8) e `STATUS[1]` refletia `array_done`, que pulsa a
cada linha. Mesmo com o start corrigido, o software veria `done` apos a linha 0 e
leria um tile com as outras 7 linhas ainda nao computadas.

**Correcoes.** No wrapper, `op_busy`/`op_done` de nivel de operacao, setados ao
sair de `S_IDLE` e em `S_DONE` respectivamente, expostos em `STATUS[0]`/`STATUS[1]`
no lugar dos sinais do array. No driver, `accel_run_and_wait()` escreve `0` antes
de `1` para gerar a borda, e volta a `0` ao final.

**Por que `test_systolic_accel` passava.** Ele faz uma unica operacao logo apos o
reset: o defeito A nao aparece (a primeira borda funciona) e o B so nao aparece
porque o laco de polling da CPU e lento o bastante para, na maioria das vezes,
so ler `STATUS` depois das 8 linhas terem terminado. Era um acerto por
coincidencia de temporizacao, nao uma validacao.

**Como foi encontrado.** O benchmark SW-vs-HW ja acusava "64 elementos
divergentes" e estava documentado como limitacao em aberto, com a suspeita
apontando para `accel_driver.c` (padding ou zero-point). Mas ele so dizia QUE
divergia. Ao imprimir os valores, o padrao apareceu: a coluna 0 do HW era
constante nas 8 linhas enquanto a do SW variava -- o indice da linha nao estava
afetando o resultado. Mesma licao do caso da SDRAM: um teste que diz apenas
"passou/falhou" nao localiza nada.

**Resultado** (imagem `img_07_label7.bin`, referencia em `out/expected.txt` gerada
por `build_mnist_int8.py`):

```
[logits] -20 -15 18 17 -12 -21 -96 87 -1 24     <- identico a referencia
>>> Classe prevista: 7 <<<                      <- rotulo correto

=== Benchmark SW vs HW (matmul 8x8x8 INT8) ===
SW (CPU):        33350 ciclos
HW (acelerador): 18533 ciclos
Resultados identicos (OK)                       <- eram 64 divergentes
```

Speedup de 1,80x. Os numeros de benchmark anteriores a esta correcao nao medem
computacao: mediam o tempo de reler resultados obsoletos.

**Nota sobre o pipeline de referencia.** `build_mnist_int8.py` (PyTorch) substitui
o `export_weights.py` (TFLite) porque simula a aritmetica do firmware bit a bit --
requantizacao em float32 com arredondamento "half away from zero", igual ao
`requantize()` do `inference.c`. O TFLite requantiza internamente com multiplicador
inteiro e deslocamento, de modo que suas saidas divergiriam do firmware por
arredondamento, ruido impossivel de distinguir de bug real. O script tambem gera
ativacoes douradas por camada (`out/golden/<imagem>/*.bin`). Consequencia pratica:
`weights.bin` e `model_meta.h` precisam vir sempre do mesmo gerador, na mesma
execucao -- carregar pesos novos sobre escalas antigas nao falha visivelmente,
so devolve numeros errados com cara de certos.

## Limitações conhecidas (documentar no TCC, Cap. 3.11)

Resolvidos e fora desta lista: classe prevista incorreta, divergência SW×HW no
benchmark (ambos pelas correções das seções acima) e o `%02u` na linha de speedup.
Relato completo em `rtl/core/docs/Diario de Bring-up.md`.

- **Access faults transitórios na SDRAM**: ~14 700 por inferência, todos
  recuperados pelo retry de `sdram.c`. A causa no controlador não foi isolada, e
  os ciclos gastos em retry entram nos tempos por camada.
- **Divisão de 64 bits trava o firmware**: `__udivdi3` na linha de speedup parava a
  execução no meio da impressão. A conta foi reescrita em 32 bits; o mecanismo do
  travamento não foi identificado.
- **Reinicializações espontâneas**: a placa reiniciou sozinha pelo menos duas vezes
  no laço de espera. Não investigado.
- **Parâmetros do IS42S16320D no SDC** preenchidos de memória, pendentes de
  conferência na folha de dados.
- **Quantização por canal fora do `main`**: o firmware usa uma escala de peso por
  camada, coerente com o `build_mnist_int8.py`. Para voltar ao pipeline TFLite
  (`export_weights.py`, quantização por canal), reaplicar o commit `9f77c8c3` do
  branch `backup/main-per-channel-quantization`.
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
