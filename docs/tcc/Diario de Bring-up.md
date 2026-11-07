# Diário de Bring-up — Acelerador Sistólico + Inferência MNIST na DE2-115

Relato cronológico dos problemas encontrados ao levar o acelerador sistólico 8×8
INT8 e a inferência completa (Fases 1–4 do TCC) do "compila sem erro" até "roda
certo em hardware físico", e de como cada um foi diagnosticado e corrigido.

O trabalho aconteceu em **duas sessões**:

- **Sessão 1** (seções 1–8): bring-up da UART, do acelerador e da SDRAM, até a
  primeira inferência completa na placa. Várias conclusões desta sessão estavam
  **erradas**. Elas foram mantidas no texto, marcadas com **⚠ Revisto na sessão 2**,
  porque o caminho errado também é resultado: custou tempo e mostra quais métodos
  falharam.
- **Sessão 2** (seção 9): encontrou as causas reais da corrupção da SDRAM e da
  divergência do acelerador, e levou a inferência a bater bit a bit com a
  referência. Está descrita em detalhe, no formato da monografia, em
  [`Registro de Depuracao - Bring-up em Hardware.md`](Registro%20de%20Depuracao%20-%20Bring-up%20em%20Hardware.md).
  Este diário resume esse registro e o liga ao que veio antes.

A seção 10 lista o que ainda está em aberto. A seção 11 é uma retrospectiva do que a
sessão 1 concluiu errado, e por quê.

### Situação de cada problema

| Problema | Situação | Onde |
|---|---|---|
| Porta `weight_i` inexistente (síntese) | ✅ Resolvido | 1 |
| Upload via bootloader / UART | ✅ Resolvido | 2 |
| Start do acelerador (nível × borda) | ✅ Resolvido (sessão 1 corrigiu só metade) | 3, 9.4 |
| `DRAM_CLK` sem PLL | ✅ Resolvido na sessão 2 (a sessão 1 achou que tinha resolvido) | 4.1, 9.2 |
| tWR ausente no controlador SDRAM | ✅ Resolvido | 4.2 |
| Corrupção silenciosa da SDRAM | ✅ Resolvido: endereço Wishbone não registrado + PLL | 9.1, 9.2 |
| Timing da interface FPGA↔SDRAM não analisado | ✅ Resolvido (SDC completo) | 9.3 |
| Divergência SW×HW no benchmark (64/64) | ✅ Resolvido: dois defeitos na interface do acelerador | 7, 9.4 |
| Classe prevista errada / não determinística | ✅ Resolvido: logits batem bit a bit com a referência | 6, 9.5 |
| Access faults transitórios na SDRAM | 🔶 Causa achada em simulação (sessão 3); falta confirmar na placa | 4.3, 12.1 |
| Travamento com divisão de 64 bits no `printf` | ⚠ Contornado, mecanismo desconhecido | 10 |
| Reinicializações espontâneas da placa | ⚠ Em aberto, não investigado | 10 |

---

## 1. Erro de síntese: porta `weight_i` inexistente

**Sintoma** (Quartus, Analysis & Synthesis):
```
Error (10349): VHDL Association List error at neorv32_systolic_top.vhd(256):
  formal "weight_rows_i" does not exist
Error (10346): formal port or parameter "weight_i" must have actual or default value
```

**Causa raiz**: `tcc_systolic_array.vhd` tinha sido atualizado para receber um
tile de pesos **completo** por PE (`weight_i`, um valor INT8 independente por
posição `(linha, coluna)`), substituindo a versão anterior, que só recebia um vetor
de 8 pesos **broadcast** para todas as colunas de uma linha (`weight_rows_i`). A
versão antiga só realizava produto matriz×vetor, incapaz de multiplicar dois tiles
8×8 completos. Três consumidores do array não foram atualizados junto:
`neorv32_systolic_top.vhd`, `neorv32_systolic_accelator.vhd` (variante CFS legada) e
`neorv32_systolic_standalone_test.vhd` (teste de LED sem CPU). Nenhum dos três está
no caminho de dados usado de fato (esse é o `tcc_systolic_wb_accelerator.vhd`),
mas o Quartus analisa **todo** arquivo listado no `.qsf`, usado ou não.

**Solução**: os três arquivos foram atualizados para o novo protocolo de tile
completo, cada um adaptando a FSM de carga de pesos ao novo formato.

---

## 2. Bring-up do upload via bootloader (UART)

Uma sequência de problemas empilhados, cada um mascarando o próximo até ser corrigido.

### 2.1 Toolchain fora do PATH
`riscv-none-elf-gcc` não encontrado. O toolchain (xPack RISC-V GCC) já estava
instalado em `/opt/riscv-none-elf-gcc/bin` e só faltava no `PATH`. Corrigido
descomentando a linha já existente no `~/.zshrc`.

### 2.2 Cabo errado
O upload via bootloader não respondia porque o cabo conectado era o do
**USB-Blaster** (JTAG, só programa a FPGA), não o da **UART**, que sai pelo conector
**RS-232 DB9** da placa. Com o cabo certo, o banner do bootloader apareceu no minicom.

### 2.3 Handshake de pesos: `'R'` enviado uma vez só
O handshake de pesos (`send_weights.py`) dava timeout esperando `'R'` (ready).
`sdram_uart_handshake_loop()` mandava o `'R'` **uma única vez** antes de bloquear
esperando comando. Se o host conectasse um instante depois, perdia a única janela.
**Corrigido**: reenviar `'R'` periodicamente, com poll fino de 1 ms. Um `sleep` longo
criaria uma janela cega em que o FIFO de RX estoura antes de o firmware voltar a
checar a UART.

### 2.4 Rajadas contínuas perdem bytes
Uploads maiores (o firmware via bootloader, depois os ~422 KB de `weights.bin`)
falhavam de forma inconsistente. Às vezes corrompiam até o texto do banner do
bootloader (`"Te 'ohlp"` em vez de `"Type 'h' for help"`), o que confirmava perda de
bytes real, não erro de lógica.

**Corrigido em duas camadas**:
- Upload do firmware (`sw/image_gen/uart_upload.sh`, e `uart_upload.py` na sessão 2):
  envio em pedaços pequenos com pausa entre eles.
- Upload de pesos e imagem (`tools/send_weights.py` + `sdram.c`): pedaços de 64 B
  **confirmados individualmente** (`'K'` = ok, `'N'` = falhou), com retry pelo host.
  Só o throttling não bastava para ~400 KB: mesmo uma taxa de perda baixa garante
  pelo menos uma falha em milhares de pedaços.

> **⚠ Revisto na sessão 2.** A sessão 1 atribuiu a perda ao chip CH340 do adaptador.
> Na sessão 2, o envio em rajada contínua falhou também com um adaptador FTDI de boa
> qualidade, e travou a placa. O ritmo de 16 B a cada 10 ms limita a vazão a
> ~1600 B/s, abaixo dos 1920 B/s que 19200 baud permitem. O limite é o que o
> **bootloader** consegue absorver, não o cabo.

### 2.5 `uart_getc()` não bloqueante no bootloader
`uart_getc()` fazia uma checagem não bloqueante antes de ler e retornava `0` na
hora se nenhum byte tivesse chegado, quebrando a leitura do stream de upload.
**Corrigido** chamando direto a função de baixo nível, que já é bloqueante. Na
prática, a causa dominante era o FIFO de 1 byte (2.6), mas a correção continua
válida e foi mantida.

### 2.6 FIFO de RX da UART pequeno demais
`IO_UART0_RX_FIFO` tinha o valor padrão de **1 byte**. Qualquer byte que chegasse
enquanto o firmware estava ocupado era perdido. **Corrigido**:
`IO_UART0_RX_FIFO => 64` no generic map do `neorv32_top`.

### 2.7 UART da aplicação a 115200 baud (sessão 2)
A transferência dos 422 KB de pesos a 19200 baud levava ~220 s. A UART da aplicação
é independente da do bootloader: o bootloader fica em 19200 (fixo em
`sw/bootloader/config.h` e embutido no bitstream) e só transfere os ~16 KB do
firmware. Por isso a aplicação pode subir de velocidade só recompilando o firmware:
`APP_UART_BAUD = 115200` em `main.c`, o que reduz a transferência para ~40 s. A
vazão se autolimita, porque o protocolo confirma a cada 64 bytes e o FIFO de RX tem
64 entradas.

Consequência prática: o terminal serial fica em **19200** durante o upload do
firmware e em **115200** para a saída da aplicação e para o `send_weights.py`
(`--baud 115200`).

### 2.8 Upload pelo Windows (sessão 2)
`uart_upload.sh` depende de bash e de um `stty` funcional. O `stty` do MSYS/Git Bash
não configura portas COM: falha em `raw` e `cread`, e o script aborta antes de
enviar qualquer byte. Foi adicionado `sw/tcc/tools/uart_upload.py`, que fala o mesmo
protocolo e só precisa de `pyserial` (alvo `make upload_py`). Além disso, o
`image_gen.c` inclui `<elf.h>`, que o MinGW não traz. Foi adicionado um `elf.h`
mínimo em `tools/win_compat/`, e o `neorv32_exe.bin` gerado é idêntico byte a byte ao
gerado com o toolchain xPack.

---

## 3. FSM do acelerador sistólico (Wishbone): start por nível

**Sintoma**: depois de corrigir a UART, o teste `test_systolic_accel` parecia
travar ou demorar demais, e o Teste 3 (IRQ) falhava de forma inconsistente.

**Causa raiz**: em `tcc_systolic_wb_accelerator.vhd`, `start_req` era calculado
a partir do **nível** do bit 0 de CTRL (`ctrl_reg(0) and not busy and not clear`),
não da **borda** de subida. Como o software nunca zerava esse bit, assim que a FSM
voltava para `S_IDLE`, `ctrl_reg(0)` continuava em `'1'` e a operação disparava de
novo sozinha, em loop invisível para o software.

**Solução**: detecção de borda (compara `ctrl_reg(0)` com o valor do ciclo
anterior).

> **⚠ Revisto na sessão 2 — a correção estava pela metade.** A RTL passou a exigir
> uma borda, mas o driver (`accel_driver.c`) continuou escrevendo `0x1` sem nunca
> voltar a zero. A partir daí, **só a primeira operação depois do reset** produzia
> borda. Da segunda em diante o array não iniciava. Como o `done` da operação
> anterior continuava ativo, o polling terminava na hora e o driver lia o resultado
> do tile anterior. Havia ainda um segundo defeito, independente: o `STATUS.done`
> exposto era o do array, que pulsa a cada uma das 8 linhas, e não o da operação
> inteira. Os dois estão na seção 9.4.
>
> O `test_systolic_accel` passava por coincidência. Ele roda uma única operação
> logo após o reset, e o polling da CPU é lento o bastante para ler o estado só
> depois das 8 linhas terminarem.

---

## 4. SDRAM: da simulação "perfeita" ao hardware real

O controlador SDRAM (`tcc_sdram_controller.vhd`) passava 100% nos testbenches
GHDL, com modelo comportamental ideal de SDRAM, mas falhava consistentemente em
hardware real.

### 4.1 `DRAM_CLK` sem PLL
A versão original gerava `DRAM_CLK` com um **inversor combinacional puro**
(`not clk_i`) ligado direto ao pino de saída. Sem PLL ou rede de clock dedicada, a
fase real do sinal na placa fica sujeita ao atraso de roteamento genérico do FPGA,
algo que a simulação não captura.

A sessão 1 gerou um PLL dedicado (`sdram_clk_pll_core`, ALTPLL) e registrou o
problema como "corrigido com defasagem de −3 ns".

> **⚠ Revisto na sessão 2 — o PLL nunca chegou ao pino.** No commit `27b6f5f3`, o
> PLL foi instanciado com `c0 => open`, e `dram_clk_o <= not clk_i` continuou no
> top-level sob o comentário "DIAGNÓSTICO TEMPORÁRIO". O PLL existia só para
> fornecer o `locked` usado no reset da SDRAM. Portanto a defasagem configurada
> nunca esteve em vigor, e o clock da memória continuou saindo do inversor
> combinacional, exatamente a condição que o PLL deveria eliminar.
>
> Também não era −3 ns: o código sempre teve `-2000` ps. A sessão 2 ligou `c0` ao
> pino, com defasagem de 180° (`-10000` ps). Ver seção 9.2.

**Obstáculo à parte**: a GUI do Quartus 18.1 (IP Catalog/MegaWizard) **travava**
neste ambiente ao gerar o PLL. As bibliotecas de que a GUI depende (`libpng12.so.0`,
`libccl_*`, `libQtCore.so.4` etc.) só existem dentro da instalação do Quartus. A
solução foi gerar o PLL por linha de comando (`qmegawiz -silent`) com
`LD_LIBRARY_PATH` apontando para essas pastas. Pegadinha: o nome do arquivo de saída
**precisa** terminar em `.vhd`, senão o `qmegawiz` falha em silêncio (exit code 2,
sem mensagem).

### 4.2 tWR (write recovery) nunca respeitado
O controlador esperava tRP/tRCD/tRC/tMRD, mas **nunca esperava tWR**, o intervalo
mínimo entre o comando WRITE e o PRECHARGE seguinte. **Corrigido**: novo estado
`S_WRITE_RECOVER` na FSM, com o generic `T_WR_CYCLES`. Esta correção continua
válida.

### 4.3 Access faults transitórios
Acessos isolados à SDRAM falhavam esporadicamente. O sintoma inicial parecia um
travamento silencioso da CPU. Instalar `neorv32_rte_setup()` mostrou que eram
**Store/Load access faults** genuínos: o `XBUS_TIMEOUT` (2048 ciclos) detectava que o
controlador não confirmava (`ack`) a tempo. O handler padrão do RTE avança o `MEPC` e
pula a instrução, perdendo o dado sem aviso.

**Mitigação**: `sdram_install_fault_retry_handler()` (`sdram.c`) instala um handler
para `TRAP_CODE_L_ACCESS`/`TRAP_CODE_S_ACCESS` que **recua o `MEPC`**, fazendo a
mesma instrução executar de novo.

> **Sessão 2.** Continua **em aberto**. Com a SDRAM já íntegra, a inferência completa
> acumula cerca de **14 700** faults, todos recuperados. Os dados corretos refletem o
> retry funcionando, não a ausência da falha, e cada retry consome ciclos que entram
> nas medições por camada. O limite de retries consecutivos caiu de 100 000 para
> 64: cem mil tentativas seguidas não distinguem uma falha transitória de uma
> permanente, que era o propósito do limite.

> **Sessão 3.** Causa encontrada em simulação (12.1): o controlador só registrava um
> pedido em `S_IDLE`, e o `stb` do XBUS dura um ciclo. Um `stb` que chegasse durante
> um AUTO REFRESH se perdia. Falta confirmar na placa que os faults zeraram.

### 4.4 Resultados variando entre gravações
O mesmo bitstream às vezes funcionava e às vezes não, só reprogramando a placa. A
sessão 1 atribuiu isso à gravação via JTAG/USB-Blaster.

> **⚠ Revisto na sessão 2.** A explicação por JTAG nunca foi confirmada e deixou de
> ser necessária. Naquele momento, o clock da memória saía de um inversor
> combinacional, a interface FPGA↔SDRAM não tinha nenhuma restrição de timing e o
> endereço da requisição acompanhava o barramento de forma combinacional (9.1). Um
> sistema operando nessa margem pode variar entre energizações sem que o bitstream
> mude. Depois das correções da sessão 2, esse comportamento não foi mais relatado.

---

## 5. Ferramentas de linha de comando do Quartus (sem GUI)

Com a GUI travando (4.1), o Quartus 18.1 local (`~/intelFPGA_lite/18.1`) foi operado
inteiramente por linha de comando:

```bash
export QUARTUS_ROOTDIR=~/intelFPGA_lite/18.1/quartus
export PATH="$QUARTUS_ROOTDIR/linux64:$QUARTUS_ROOTDIR/bin:$PATH"
export LD_LIBRARY_PATH="$QUARTUS_ROOTDIR/linux64:$QUARTUS_ROOTDIR/../lib/usr/lib/x86_64-linux-gnu:$LD_LIBRARY_PATH"

quartus_sh --flow compile neorv32_mnist_accel
```

A sessão 2 usou o Quartus **25.1**, que regenerou os arquivos do PLL. A comparação
mostrou parâmetros idênticos (mesma fase, divisor e modo). Mudaram só as strings de
versão e a renomeação Intel/Altera (commit `1f3a76a3`).

---

## 6. Quantização: previsão errada na primeira inferência

**Sintoma**: a primeira inferência completa previu classe **8** para uma imagem de
rótulo **2**, com logits saturados (dois valores no teto de INT8, a maioria no
piso).

**Diagnóstico da sessão 1**: o TFLite quantiza pesos de conv/dense **por canal de
saída** (32/64/128/10 escalas para conv1/conv2/dense1/dense2), mas
`export_weights.py` lia só `scales[0]` e o firmware aplicava esse valor à camada
inteira. A correção exportou o array completo de escalas (`ws_offset` em
`model_meta.h`) e passou a aplicar um multiplicador por canal em `inference.c`. A
imagem passou a prever classe 2.

A mesma sessão registrou duas observações em aberto: os logits continuavam
saturando mais que a referência (a classe 2 saía "por ordem de empate" em 127), e,
rodando de novo sem nenhuma mudança, a placa previu classe **5**.

> **⚠ Revisto na sessão 2.** O diagnóstico de quantização por canal estava correto
> para o pipeline TFLite, mas não era a causa da saturação nem do não determinismo.
> Durante toda a sessão 1, o acelerador só computava de verdade a primeira operação
> após o reset. A inferência inteira rodava sobre resultados obsoletos (seção 9.4).
> Somava-se a isso a SDRAM lendo e escrevendo na palavra vizinha (9.1). O "acerto"
> da classe 2 não era evidência de correção.
>
> **Estado atual do pipeline de pesos.** A sessão 2 trocou o `export_weights.py`
> (TFLite) pelo `build_mnist_int8.py` (PyTorch), que gera `weights.bin`,
> `model_meta.h` e uma referência que simula a aritmética do firmware **bit a bit**:
> requantização em float32 com arredondamento "half away from zero", igual ao
> `requantize()` de `inference.c`. O TFLite requantiza com multiplicador inteiro e
> deslocamento, e a diferença de arredondamento seria indistinguível de um bug real.
> Com essa referência, os 10 logits batem exatamente (9.5).
>
> O `main` atual usa **uma escala de peso por camada** (`w_scale`). A correção por
> canal (`ws_offset`) não está no `main`: ela foi preservada no branch
> `backup/main-per-channel-quantization` (commit `9f77c8c3`). Se o pipeline TFLite
> voltar a ser usado, essa correção precisa ser reaplicada. O `build_mnist_int8.py`
> ficou no ambiente da sessão 2 e não está neste repositório; por isso não foi
> possível conferir aqui se o modelo PyTorch é quantizado por tensor por construção.
>
> **Regra prática**: `weights.bin` e `model_meta.h` precisam vir do mesmo gerador, na
> mesma execução. Carregar pesos novos sobre escalas antigas não gera erro nenhum,
> só números errados com cara de certos. MNIST e Fashion-MNIST produzem exatamente
> 422 344 bytes, então nem o tamanho denuncia a troca.

---

## 7. Divergência SW-vs-HW no benchmark

O benchmark (matmul 8×8×8, CPU × acelerador) reportava os 64 elementos divergentes
depois da inferência. Repetido 30 vezes seguidas logo no boot, passava 100%.

A sessão 1 concluiu que a falha estava correlacionada com uso prolongado da SDRAM e
levantou a hipótese de degradação de margem de timing do acelerador por
aquecimento. **A hipótese térmica foi descartada ainda na sessão 1**: o padrão
aparecia com a placa ligada havia pouco tempo.

> **⚠ Revisto na sessão 2 — resolvido, e a causa era outra.** Eram os dois defeitos
> da interface do acelerador (9.4). Isso explica também a observação que parecia
> contraditória:
>
> - **30/30 no boot**: a primeira operação após o reset era real. As 29 seguintes não
>   iniciavam e devolviam o resultado anterior, mas, como o benchmark repete a
>   **mesma entrada**, o resultado obsoleto era igual ao correto.
> - **64/64 depois da inferência**: a última operação real tinha sido um tile da
>   inferência, com outros dados. O benchmark relia esse tile.
>
> A correlação nunca foi com a SDRAM. Era com "o acelerador já ter sido usado desde o
> reset". O benchmark só dizia *que* havia divergência. Impressos os valores, a
> coluna 0 do resultado de hardware era constante nas 8 linhas, e o índice da linha
> não alcançava o resultado.

---

## 8. Ciclos de inferência

Na sessão 1, uma inferência completa levava ~7 s a 50 MHz. Parte disso se explica
por limitações conhecidas do projeto:

1. **Sem FPU de hardware**: toda `float` em `requantize()` roda em soft-float (só o
   conv1 chama a função 784×32 = 25 088 vezes).
2. **SDRAM em política close-page**: cada acesso faz ACTIVE→(R/W)→PRECHARGE, sem
   burst nem DMA.
3. **Acelerador via MMIO com polling**: cada tile 8×8 exige escrever WEIGHT e ACT
   registrador por registrador e esperar o `done` em loop.

> **⚠ Revisto na sessão 2.** Os tempos da sessão 1 **não medem computação**: o
> acelerador não iniciava depois da primeira operação. Com as correções, o
> benchmark mede **33 350 ciclos em software e 18 533 no acelerador, ganho de
> 1,80×**, com resultados idênticos. Os tempos por camada atuais incluem os ciclos
> gastos nos ~14 700 retries de access fault (4.3).

A maior alavanca de desempenho futura continua sendo trocar a requantização em
`float` por ponto fixo inteiro. Isso exigiria gerar a referência com a mesma
aritmética (seção 6).

---

## 9. Sessão 2: as causas reais

Resumo do [`Registro de Depuracao - Bring-up em Hardware.md`](Registro%20de%20Depuracao%20-%20Bring-up%20em%20Hardware.md),
onde estão a metodologia completa e as hipóteses descartadas.

### 9.1 Endereço Wishbone não registrado no controlador SDRAM (`193b7e17`)

**O teste que revelou**: o smoke test de 16 bytes só dizia *que* havia erro. Foi
substituído por `sdram_diag.c`, que localiza. Com padrões uniformes (`0x00000000`,
`0xFFFFFFFF`, `0xAAAAAAAA`, `0x55555555`) em 256 palavras de quatro regiões: **zero
erros**. Com o próprio endereço como dado: **256 palavras erradas de 256**, em todas
as regiões.

Padrões uniformes são cegos a erros de endereçamento: se toda posição contém o mesmo
valor, ler da posição errada devolve o valor certo. Uma segunda armadilha: com
valores `TAG+i`, palavras vizinhas diferem em um único bit, e "leu o endereço
errado" fica indistinguível de "bit 0 corrompido". Com `TAG+i*0x55`, uma leitura do
endereço errado ainda devolve um múltiplo válido de `0x55`, e as duas causas se
separam.

**Causa**: o processo `latch_req` registrava `req_wdata`, `req_sel` e `req_we` ao
aceitar a requisição, mas **não o endereço**. `req_addr <= wb_adr_i(26 downto 2)` era
uma atribuição concorrente e acompanhava o barramento durante toda a FSM. Como a FSM
leva vários ciclos entre ACTIVE e READ/WRITE, qualquer movimento de `wb_adr_i` nesse
intervalo fazia o ACTIVE capturar a linha de um endereço e o READ/WRITE a coluna de
outro, gravando e lendo a palavra vizinha.

**Correção**: registrar `req_addr` junto com o restante da requisição.

**Por que a simulação não pegou**: a testbench mantém o endereço estável durante a
transação inteira, como faz naturalmente um teste escrito à mão. O mestre Wishbone
real não mantém.

### 9.2 PLL de fato ligado ao `DRAM_CLK` (`d59ced4a`)

Ver 4.1: `c0` estava desconectado desde `27b6f5f3`. A correção ligou `c0` ao pino com
defasagem de **180°** (`-10000` ps a 50 MHz). É a relação que a FSM pressupõe: ela
muda endereço e comando na borda de `clk_i` e espera que o chip amostre meio ciclo
depois, agora pela rede de clock dedicada do PLL.

| configuração | palavras erradas (endereço como dado) | classificadas como endereço |
|---|---|---|
| inicial | 1024 | 100% |
| endereço registrado (9.1) | 153–159 | 0 |
| PLL ligado a 180° (9.2) | **0** | 0 |

Resultado final da bateria: **0 palavras com erro em 5120**, em quatro regiões e
cinco padrões, com as duas metades do barramento íntegras.

### 9.3 Restrições de timing da interface de memória (`d59ced4a`)

O `.sdc` tinha quatro linhas e declarava só `clk_i`: nenhum clock derivado para a
saída do PLL, nenhum atraso de entrada ou saída nos pinos da SDRAM. A folga de
5,49 ns reportada cobria só a lógica interna, e o fitter roteava os pinos da memória
sem meta temporal. Com a interface restrita, a mesma compilação passou a acusar
**violação de 2,88 ns** no caminho de leitura `dram_dq_io[*] → clk_i`.

| domínio | antes (SDC incompleto) | depois |
|---|---|---|
| lógica interna | 5,49 ns | 3,26 ns |
| interface de memória | não analisada | 2,33 ns |
| caminho de leitura | violava em 2,88 ns | atende |

**A análise de timing sozinha escolheu a fase errada.** Uma varredura com o SDC novo
indicou 0 ps como ótimo (+4,13 ns leitura, +7,11 ns escrita). Em hardware, 0 ps
deslocou todo acesso em exatamente uma palavra. O mapa de erros por bit virou 1024,
512, 256, 128, 64, 32, 16, 8, a assinatura de somar 4 bytes com propagação de
vai-um. Em fase 0, o chip amostra na mesma borda em que o FPGA muda o barramento, e
o TimeQuest resolve isso escolhendo a borda de captura seguinte, relação que a FSM
não implementa. Um SDC fiel precisaria de `set_multicycle_path` declarando qual
ciclo captura cada comando. O SDC tornou o problema visível e quantificável, mas o
valor teve de ser validado em hardware.

Os parâmetros do IS42S16320D usados no SDC ainda precisam ser conferidos na folha de
dados, e os atrasos de trilha da placa são estimativas (seção 10).

### 9.4 Interface do acelerador: start por borda e `done` por operação (`df32b218`)

Dois defeitos independentes, ambos tornando o acelerador inútil depois da primeira
operação:

1. **O start nunca gerava borda.** A FSM dispara na borda de subida de `CTRL[0]`
   (correção da seção 3), mas o driver escrevia `0x1` e nunca voltava a zero. Só a
   primeira operação depois do reset iniciava. **Correção**: `accel_run_and_wait()`
   escreve `0`, depois `1`, e volta a `0` ao final.
2. **`STATUS.done` era por linha, não por operação.** O wrapper roda o array 8 vezes,
   uma por linha do tile, e `STATUS[1]` carregava o `array_done`, que pulsa a cada
   linha. Mesmo com o start corrigido, o software veria `done` depois da linha 0 e
   leria um tile com sete linhas não computadas. **Correção**: sinais `op_busy` e
   `op_done` no wrapper, ativados ao sair de `S_IDLE` e em `S_DONE`, expostos no
   lugar dos sinais do array.

### 9.5 Resultado

Imagem de teste de rótulo 7 (`img_07_label7.bin`), comparada com a referência de
`build_mnist_int8.py` (`out/expected.txt`):

```
obtido:   -20 -15 18 17 -12 -21 -96 87 -1 24
esperado: -20 -15 18 17 -12 -21 -96 87 -1 24
classe prevista: 7

SW (CPU):        33350 ciclos
HW (acelerador): 18533 ciclos
Resultados identicos
```

Os dez logits coincidem individualmente. O sistema também rodou com um segundo
conjunto de dados (Fashion-MNIST), trocando só os pesos e os parâmetros de
quantização, o que mostra que o acelerador é genérico e não ajustado a um problema
específico. O `model_meta.h` do `main` atual contém os parâmetros do Fashion-MNIST
(commit `29097a2e`).

### 9.6 Demonstração sem terminal: LCD, KEY1 e laço de imagens (`97bdbc63`, `446189a1`)

- **LCD 16×2 (HD44780)** acionado por GPIO (`lcd.c`): dados em `gpio[15:8]`, RS em
  `gpio[16]`, EN em `gpio[17]`, RW fixo em 0 e ON/BLON fixos em 1 no top-level. O
  GPIO passou de 8 para 32 bits. Com RW em 0 não dá para ler o busy flag, então o
  driver usa os tempos da folha de dados com margem, e `delay_us` é construído sobre
  o contador de ciclos. Como `neorv32_gpio_port_get()` lê os pinos de entrada e não o
  latch de saída, o driver mantém uma cópia em software do estado.
- **Todas as etapas no display**: teste da SDRAM, aguardando imagem, recebendo pesos,
  pesos na SDRAM, recebendo imagem, inferindo (com o nome da camada), classe.
- **KEY[1]** estava ligado a um pino mas a nenhum sinal: a entrada de GPIO do
  NEORV32 não estava conectada no top-level. Agora chega em `gpio_i(0)`, invertido
  (o botão é ativo-baixo), com debounce de 20 ms. O resultado fica no display até
  um clique.
- **Laço de imagens**: `main()` volta ao handshake depois de cada inferência. Os
  pesos ficam na SDRAM, então testar outra imagem custa segundos em vez de reenviar
  422 KB e refazer o upload. `send_weights.py` aceita `--weights` como opcional.

---

## 10. Questões em aberto

- **Access faults transitórios**: causa encontrada e corrigida em simulação (12.1).
  Falta rodar a inferência na placa e ver `[faults ate aqui: 0]`.
- **Travamento com divisão de 64 bits**: a linha de speedup do benchmark usava
  `(uint32_t)(((uint64_t)(cyc_sw % cyc_hw) * 100u) / cyc_hw)`. O cast para 64 bits
  força uma chamada a `__udivdi3` (RISC-V não divide 64 bits em hardware), e a
  execução parava no meio de um texto literal, de forma reprodutível. O cast era
  desnecessário (o resto é no máximo ~18 532, vezes 100 cabe em 32 bits) e a conta
  voltou a ser de 32 bits, com um comentário para ninguém "corrigir" de volta. Por
  que `__udivdi3` travava continua sem explicação.
- **Reinicializações espontâneas**: a placa reiniciou sozinha pelo menos duas vezes,
  depois de entrar no laço de espera. Não foi investigado. Hipóteses: ruído no pino
  de reset ou queda de tensão ao energizar o display.
- **Parâmetros do chip no SDC**: os tempos do IS42S16320D foram preenchidos de
  memória e estão marcados como pendentes de conferência na folha de dados. Não
  afetam o funcionamento atual, porque a fase foi validada em hardware, mas afetam a
  confiabilidade do relatório de timing em recompilações futuras.
- **Quantização por canal fora do `main`**: ver seção 6.

## 11. Retrospectiva: o que a sessão 1 concluiu errado

Ao final da sessão 1, a corrupção da SDRAM chegou a ser tratada como **limitação
física da placa** (um problema elétrico no chip 0, pinos `DQ[15:8]`), e a
investigação foi encerrada. A sessão 2 mostrou que era um bug de RTL. Os passos que
levaram à conclusão errada:

| Evidência da sessão 1 | O que parecia provar | O que de fato acontecia |
|---|---|---|
| Testbench GHDL reproduzindo o acesso do firmware passou 32/32 | A lógica do controlador está correta | A testbench segurava `wb_adr_i` estável até o `ack`, o único cenário em que o defeito de 9.1 não aparece |
| Erros concentrados nos bytes baixos (lanes 0/1, chip 0) | Defeito físico no chip 0 | A sessão 2 viu a mesma concentração e mostrou que era artefato do teste: os bits altos dos valores gravados eram iguais entre palavras vizinhas, então ler a palavra errada "acertava" ali (Registro, 3.2). O teste de bytes da sessão 1 não foi reanalisado, mas, após as correções, as duas metades do barramento ficaram com zero erros |
| Varredura de fase do PLL de −6000 a +2000 ps sem efeito | A fase do clock não é a causa | O top-level em uso era o de `27b6f5f3`, com o `c0` do PLL desconectado (4.1). A varredura mudava a fase de um sinal que não saía do FPGA |
| O mesmo `.sof` dava resultados diferentes entre gravações | Gravação JTAG instável | Sistema operando sem margem (clock combinacional, interface sem restrição, endereço combinacional). Não é preciso JTAG para explicar |
| Benchmark passa 30/30 no boot e falha depois da inferência | Correlação com uso da SDRAM ou aquecimento | O acelerador só iniciava na primeira operação, e o benchmark repete a mesma entrada (seção 7) |
| Timing com 5,49 ns de folga | A interface tem margem | O SDC não restringia nenhum pino da SDRAM (9.3) |
| Pinagem `DRAM_*` conferida contra a referência da DE2-115 | O `.qsf` está correto | Correto. Esta verificação continua válida |

O padrão comum: **testes de aprovado/reprovado e testes que não exercitam a condição
real**. A testbench modelava um mestre idealizado; o smoke test dizia *que* falhava e
não *onde*; o relatório de timing cobria só a lógica interna; e o `test_systolic_accel`
passava por coincidência de temporização. Os testes da sessão 2 que informavam
*como* a falha acontecia resolveram em minutos o que os binários não resolveram em
horas.

---

## 12. Sessão 3: DMA e array 16×16 (só simulação, sem a placa)

### 12.1 Access faults: o `stb` de um ciclo
O XBUS do NEORV32 é Wishbone *pipelined*: `xbus_stb_o` fica alto por **um ciclo** e
`xbus_cyc_o` segue alto até o `ack` (`neorv32_xbus.vhd`). O controlador SDRAM só
registrava o pedido se estivesse em `S_IDLE` nesse ciclo. Um `stb` que chegasse
durante um AUTO REFRESH (cerca de 5 ciclos fora de `S_IDLE`) ou ainda na
inicialização se perdia: ninguém respondia, e o `XBUS_TIMEOUT` virava access fault.

Isso era pior que 5 ciclos em 385. O refresh pendente só é atendido quando a FSM
volta a `S_IDLE`, que é exatamente quando o mestre manda o próximo `stb`. Por isso
quase todo refresh que vencia durante um acesso matava o acesso seguinte.

As testbenches nunca viam o problema porque o mestre delas segurava `stb` até o
`ack` (Wishbone clássico), a mesma armadilha do bug 9.1. A
`neorv32_sdram_controller_tb` ganhou uma fase com mestre igual ao XBUS: `stb` de um
ciclo, endereço trocado por lixo logo depois e timeout de 64 ciclos.

| Controlador | Acessos sem `ack`, de 400 |
| --- | --- |
| Antes (só aceita em `S_IDLE`) | 57 |
| Depois (aceita em qualquer estado sem pedido pendente) | 0 |

A correção registra o pedido em qualquer estado, desde que não haja outro em
andamento (`req_pending = '0'`), e a FSM o atende quando voltar a `S_IDLE`. Um
mestre clássico, que segura `stb`, não duplica o pedido, porque nada é aceito com
`req_pending = '1'`. Isso também era pré-requisito do DMA: ele não tem o retry que
salvava a CPU (4.3), e um access fault aborta o descritor inteiro.

Na simulação do SoC com o firmware de teste (12.3), o controlador antigo produziu
505 access faults na CPU, todos recuperados pelo retry, e **222 erros de
barramento no DMA**: todos os resultados calculados por DMA saíram errados. Com a
correção, 0 e 0.

### 12.2 Proposta A: DMA do NEORV32, cache de instruções e `wfi`
O DMA do NEORV32 fica entre a CPU e o switch de barramento, então alcança a SDRAM
e o acelerador sem RTL novo. No `neorv32_de2115_mnist_top`: `IO_DMA_EN` (fila de 16
entradas, 5 descritores), `ICACHE_EN` (8 blocos de 64 B) e dois generics,
`BOOT_MODE_SELECT` (a simulação inicia direto da IMEM) e `ACCEL_ARRAY_SIZE`.

No driver (`accel_driver.c`):
- **Tiles contíguos.** `accel_wpack` grava cada tile de pesos em T·T bytes
  seguidos, com zero fora de K×N e a soma das colunas pronta. `accel_apack` (ou o
  im2col, direto) faz o mesmo com as ativações. Cada tile vira um descritor.
- **`wfi` em vez de polling.** A CPU dorme até a IRQ do DMA. Ela acorda mesmo com
  `mstatus.MIE = 0`, sem passar por handler. Fazer polling de `DMA_CTRL` atrasaria o
  próprio DMA, porque a CPU tem prioridade fixa no switch.
- **Sobreposição.** O array copia os pesos no ciclo seguinte ao start. Por isso o
  DMA carrega os pesos do próximo tile durante o cálculo, e as ativações do
  próximo enquanto a CPU lê RESULT.
- **Medição pelo `mtime`.** O `mcycle` para enquanto a CPU dorme (`cnt_event_cy = 0`
  em `S_SLEEP`): medir com `neorv32_cpu_get_cycle()` daria um tempo menor que o real.

O wrapper ganhou o registrador INFO (`0x00C`, tamanho do array), e a IRQ passou a
subir no fim da operação, não a cada linha (o mesmo engano que o polling já tinha
corrigido em 9.4).

### 12.3 Resultados na simulação do SoC
`sim/tcc/run_soc_sim.sh` simula o top-level da placa inteiro no GHDL: NEORV32, gateway,
controlador SDRAM com modelo comportamental e acelerador, com o firmware
`sw/tcc/accel_dma_test` gravado na IMEM. Ele faz o mesmo cálculo pelos três
caminhos e confere contra uma referência em software. Todos os resultados batem.

| Caminho (ciclos) | Matmul 30×70×20, 8×8 | Matmul, 16×16 | Matvec 1×136×20, 8×8 | Matvec, 16×16 |
| --- | --- | --- | --- | --- |
| Só software | 2 702 498 | 2 618 634 | — | — |
| Acelerador, CPU move os dados | 1 335 470 | 973 711 | 561 813 | 763 839 |
| Acelerador, DMA | 428 240 | 284 674 | 53 269 | 45 091 |
| Acelerador, DMA com sobreposição | 399 134 | 266 546 | 49 410 | 36 965 |

- O DMA dá 3,3× no matmul (8×8) sobre o caminho em que a CPU move os dados.
- A sobreposição rende só 7%: o barramento compartilhado é o limite, como a
  proposta previa (cada byte cruza o barramento duas vezes).
- No matvec, o caminho antigo monta tiles inteiros para um vetor de uma linha, e
  o DMA copia só a linha 0 de ACT: 11,4× em 8×8.
- O 16×16 corta mais 1,5× o matmul com DMA. No caminho antigo, o matvec piora em
  16×16, porque a CPU monta tiles 4 vezes maiores para usar uma linha só.

### 12.4 Recursos e timing (Quartus 25.1, Cyclone IV EP4CE115)

| Configuração | LEs | Registradores | Multiplicadores 9 bits | Fmax (slow 85 °C) |
| --- | --- | --- | --- | --- |
| 8×8 + DMA + ICACHE | 11 638 (10%) | 8 523 | 64 de 532 | 62,7 MHz |
| 16×16 + DMA + ICACHE | 34 241 (30%) | 27 845 | 256 de 532 | 58,3 MHz |

As duas fecham timing a 50 MHz. Para gerar o bitstream 16×16:
`set_parameter -name ACCEL_ARRAY_SIZE 16` no `.qsf` e o firmware com `make TILE=16`.
O firmware recusa um bitstream de outro tamanho (registrador INFO).

Durante essa síntese apareceu um defeito à parte: o `.qsf` reescrito pelo Quartus
passou a listar `neorv32_cfs.vhd`, que declara a mesma entidade `neorv32_cfs` que
`neorv32_systolic_accelator.vhd`. Com as duas, a síntese para no erro 10430. A
linha foi removida, voltando ao conjunto de arquivos de antes.

---

## Resumo dos commits

### Branch `main` (igual a `origin/systolic-array-accelerator`)

| Commit | O que resolveu |
|---|---|
| `145331c6` | Acelerador sistólico 8×8 + correção do `weight_i` (seção 1) + Fases 1/2 |
| `04e6d767` | Protocolo UART robusto (chunk + ack, retry) para upload de pesos (2.3–2.4) |
| `27b6f5f3` | tWR, gating do reset pelo `locked` do PLL, retry de access fault (4.2–4.3). **O PLL ficou com `c0 => open`** (4.1) |
| `516033a5` | Upload e build pelo Windows (`uart_upload.py`, `elf.h`), `.gitignore` dos artefatos do Quartus (2.8) |
| `193b7e17` | Endereço Wishbone registrado no controlador SDRAM + `sdram_diag.c` (9.1) |
| `d59ced4a` | `DRAM_CLK` pelo PLL a 180° + SDC da interface de memória (9.2–9.3) |
| `df32b218` | Start por borda e `done` por operação no acelerador; inferência bit-exata (9.4–9.5) |
| `97bdbc63` | Estado da inferência e classe no LCD (9.6) |
| `446189a1` | Resultado retido no LCD até KEY[1]; todas as etapas no display (9.6) |
| `2dfe67f9` | `Registro de Depuracao - Bring-up em Hardware.md` |
| `29097a2e` | UART da aplicação a 115200; linha de speedup restaurada; `model_meta.h` do Fashion-MNIST (2.7, 10) |
| `1f3a76a3` | Arquivos do PLL regenerados pelo Quartus 25.1, sem mudança de parâmetros (5) |

### Branch `backup/main-per-channel-quantization` (fora do `main`)

| Commit | Conteúdo |
|---|---|
| `9f77c8c3` | Quantização por canal (`ws_offset`) para o pipeline TFLite (seção 6) |
| `f3d0a9bd`, `c90651c7` | Documentação da divergência SW×HW com as hipóteses da sessão 1, superadas pela seção 7 |
