# Systolic Array Accelerator — Guia Completo

## 1. O Problema: Por que trocar o CFS?

### Como era antes (CFS)

O acelerador estava conectado ao barramento interno do NEORV32 através do **CFS (Custom Functions Subsystem)**. O CFS é um periférico como qualquer outro (UART, GPIO, etc.) — ele fica atrás do **IO Switch**, que é um multiplexador de endereços dentro do processador.

O problema é que o barramento interno do NEORV32 trafega **32 bits por acesso**, mas o CFS recebia **1 INT8 (8 bits) por escrita**. Para preencher uma matriz 8×8 inteira:

```
64 escritas de peso (1 INT8 cada)  = 64 acessos ao barramento
64 escritas de ativação (1 INT8 cada) = 64 acessos ao barramento
64 leituras de resultado (1 INT32 cada) = 64 acessos ao barramento
─────────────────────────────────────────
TOTAL: 192 acessos ao barramento
```

Cada acesso tem latência fixa (CPU → IO Switch → CFS → ACK), então isso é **lento**.

### Como ficou agora (Wishbone/XBUS)

O **XBUS** é a porta externa do NEORV32. Ele converte o barramento interno em sinais compatíveis com o padrão **Wishbone**, que é o barramento mais usado em projetos FPGA.

A melhoria principal: agora empacotamos **4 valores INT8 dentro de cada word de 32 bits**. Então:

```
64 INT8 de peso  → 16 words de 32 bits (4 INT8 por word) = 16 acessos
64 INT8 de ativação → 16 words de 32 bits                 = 16 acessos
64 INT32 de resultado → 64 words de 32 bits               = 64 acessos
─────────────────────────────────────────────────────────────
TOTAL: 96 acessos (50% a menos que antes)
```

Além disso, o caminho CPU → XBUS é **direto**, sem passar pelo IO Switch.

---

## 2. Arquitetura do Sistema

### Visão geral dos componentes

O sistema tem **4 arquivos VHDL**:

```
┌─────────────────────────────────────────────────────────────┐
│                        NEORV32 (CPU)                        │
│                                                             │
│  ┌──────────┐     ┌──────────┐     ┌──────────────────────┐ │
│  │  CPU     │────▶│  XBUS    │────▶│ xbus_adr_o (32 bit) │ │
│  │  Core    │     │  Bridge  │     │ xbus_dat_o (32 bit) │ │
│  │          │◀────│          │◀────│ xbus_dat_i (32 bit) │ │
│  └──────────┘     └──────────┘     │ xbus_we, stb, cyc   │ │
│                                     │ xbus_ack_i, err_i   │ │
│                  (portas externas)  └──────────┬───────────┘ │
└────────────────────────────────────────────────┼────────────┘
                                                 │
                                    Sinais Wishbone
                                                 │
                                                 ▼
┌─────────────────────────────────────────────────────────────┐
│           tcc_systolic_wb_accelerator.vhd               │
│                                                             │
│   Wishbone Slave Interface                                  │
│   ┌─────────────────────────────────────────────────────┐   │
│   │  wb_adr_i ──▶ Decodificador de Endereço             │   │
│   │  wb_dat_i ──▶ Escrita de Registradores/Memória      │   │
│   │  wb_dat_o ◀── Leitura de Registradores/Memória      │   │
│   │  wb_we_i  ──▶ 1=escrita, 0=leitura                  │   │
│   │  wb_stb_i ──▶ "strobe" — indica acesso válido        │   │
│   │  wb_cyc_i ──▶ "cycle" — indica transação em curso    │   │
│   │  wb_ack_o ──▶ "acknowledge" — resposta do escravo   │   │
│   │  wb_err_o ──▶ "error" — acesso inválido              │   │
│   └─────────────────────────────────────────────────────┘   │
│                                                             │
│   ┌────────────┐  ┌────────────┐  ┌────────────┐           │
│   │ Weight Mem │  │  Act Mem   │  │ Result Mem │           │
│   │ 64 × INT8  │  │ 64 × INT8  │  │ 64 × INT32 │           │
│   └─────┬──────┘  └─────┬──────┘  └────▲───────┘           │
│         │               │               │                   │
│         ▼               ▼               │                   │
│   ┌──────────────────────────────────────────────────┐      │
│   │          FSM de Controle de Computação            │      │
│   │  S_IDLE → S_LOAD_WEIGHTS → S_LOAD_ACTS →          │      │
│   │  S_COMPUTE → S_STORE_RESULTS → S_DONE             │      │
│   └──────────────────────┬───────────────────────────┘      │
│                          │                                  │
│                          ▼                                  │
│   ┌──────────────────────────────────────────────────┐      │
│   │       tcc_systolic_array.vhd                  │      │
│   │                                                  │      │
│   │   ┌───┬───┬───┬───┬───┬───┬───┬───┐             │      │
│   │   │PE │PE │PE │PE │PE │PE │PE │PE │  ← row 0    │      │
│   │   ├───┼───┼───┼───┼───┼───┼───┼───┤             │      │
│   │   │PE │PE │PE │PE │PE │PE │PE │PE │  ← row 1    │      │
│   │   ├───┼───┼───┼───┼───┼───┼───┼───┤             │      │
│   │   │   ... 8×8 Processing Elements ...   │         │      │
│   │   ├───┼───┼───┼───┼───┼───┼───┼───┤             │      │
│   │   │PE │PE │PE │PE │PE │PE │PE │PE │  ← row 7    │      │
│   │   └───┴───┴───┴───┴───┴───┴───┴───┘             │      │
│   │                                                  │      │
│   │   Cada PE = tcc_systolic_pe.vhd              │      │
│   │   Faz: acc = acc + (activation × weight)         │      │
│   └──────────────────────────────────────────────────┘      │
└─────────────────────────────────────────────────────────────┘
```

### O que cada arquivo faz

| Arquivo | Função |
|---------|--------|
| `tcc_systolic_pe.vhd` | **Processing Element** — unidade básica. Multiplica activation × weight e acumula. |
| `tcc_systolic_array.vhd` | **Systolic Array 8×8** — conecta 64 PEs em grade, controla o fluxo de dados e o temporização. |
| `tcc_systolic_wb_accelerator.vhd` | **Interface Wishbone** — decodifica endereços, gerencia memórias de peso/ativação/resultado, e orquestra a computação via FSM. |
| `neorv32_systolic_accelator.vhd` | **Versão antiga (CFS)** — mantida como referência. Não use mais. |

---

## 3. Como o Wishbone Funciona

### O que é Wishbone?

Wishbone é um protocolo de barramento aberto para conectar módulos em FPGA. Funciona como um "contrato" entre um **mestre** (master) e um **escravo** (slave):

- O **mestre** quer ler ou escrever dados
- O **escravo** tem os dados e responde

### Os sinais

```
MESTRE (NEORV32)                          ESCRAVO (Acelerador)
─────────────────                          ──────────────────

                  ─── wb_adr_i (32 bit) ───▶    "Qual endereço?"
                  ─── wb_dat_i (32 bit) ───▶    "Dados para escrever"
                  ◀── wb_dat_o (32 bit) ───    "Dados lidos"
                  ─── wb_we_i  (1 bit)  ───▶    "0=leitura, 1=escrita"
                  ─── wb_sel_i (4 bit)  ───▶    "Quais bytes são válidos"
                  ─── wb_stb_i (1 bit)  ───▶    "Acesso acontecendo agora!"
                  ─── wb_cyc_i (1 bit)  ───▶    "Transação em curso"
                  ◀── wb_ack_o (1 bit)  ───    "Entendido, dado pronto!"
                  ◀── wb_err_o (1 bit)  ───    "Erro! Endereço inválido!"
```

### O protocolo passo-a-passo

#### Escrita (CPU escreve no acelerador)

```
Ciclo 1:                    Ciclo 2:                    Ciclo 3:
CPU quer escrever           Acelerador processa         CPU pode fazer
dado 0xABCD1234             e guarda na memória         próximo acesso
no endereço 0x90000100
                           
  wb_cyc_i = 1               wb_cyc_i = 1               wb_cyc_i = 0
  wb_stb_i = 1               wb_stb_i = 0               wb_stb_i = 0
  wb_we_i  = 1               wb_we_i  = 0               wb_we_i  = 0
  wb_adr_i = 0x90000100      wb_adr_i = X               wb_adr_i = X
  wb_dat_i = 0xABCD1234      wb_dat_i = X               wb_dat_i = X
                              wb_ack_o = 1  ◀── "OK!"    wb_ack_o = 0
```

O mestre mantém `cyc` e `stb` altos por **1 ciclo**. No ciclo seguinte, o escravo responde com `ack=1`. Isso é o modo "registered feedback" do Wishbone.

#### Leitura (CPU lê do acelerador)

```
Ciclo 1:                    Ciclo 2:                    Ciclo 3:
CPU quer ler do             Acelerador coloca            CPU recebe
endereço 0x90000900         o dado no barramento         o dado
                           
  wb_cyc_i = 1               wb_cyc_i = 1               wb_cyc_i = 0
  wb_stb_i = 1               wb_stb_i = 0               wb_stb_i = 0
  wb_we_i  = 0               wb_we_i  = 0               wb_we_i  = 0
  wb_adr_i = 0x90000900      wb_adr_i = X               wb_adr_i = X
                              wb_dat_o = 0x00000008      wb_dat_o = X
                              wb_ack_o = 1  ◀── "OK!"    wb_ack_o = 0
```

### Como o NEORV32 conecta ao Wishbone

O NEORV32 tem uma porta chamada **XBUS** (External Bus). Dentro do processador, existe um módulo chamado `neorv32_xbus` que converte o barramento interno em sinais Wishbone:

```
    Barramento Interno               XBUS (Wishbone)
    ─────────────────               ──────────────────
    bus_req_t.addr     ─────────▶   xbus_adr_o
    bus_req_t.data     ─────────▶   xbus_dat_o
    bus_req_t.rw       ─────────▶   xbus_we_o
    bus_req_t.ben      ─────────▶   xbus_sel_o
    bus_req_t.stb      ─────────▶   xbus_stb_o
    bus_req_t.stb|pending ──────▶   xbus_cyc_o
    bus_rsp_t.data     ◀─────────   xbus_dat_i
    bus_rsp_t.ack      ◀─────────   xbus_ack_i
    bus_rsp_t.err      ◀─────────   xbus_err_i
```

Quando a CPU faz um `SW` (store word) ou `LW` (load word) para um endereço que **não pertence** à memória interna nem aos periféricos IO, esse acesso é roteado automaticamente para o XBUS.

---

## 4. Mapa de Endereços do Acelerador

O acelerador usa os bits [11:8] do endereço para selecionar a região, e os bits [7:2] como offset dentro da região:

```
Endereço (byte)         Região          Conteúdo
─────────────────       ──────          ───────
BASE + 0x000            CTRL            Registradores de controle
  BASE + 0x004            CTRL          [2] irq_clear, [1] clear, [0] start
  BASE + 0x008            STATUS        [2] irq_pending, [1] done, [0] busy
  BASE + 0x00C            CONFIG        Reservado para uso futuro

BASE + 0x100            WEIGHT          Memória de pesos (8×8 = 64 INT8)
  BASE + 0x100            Word 0        bytes: w0, w1, w2, w3
  BASE + 0x104            Word 1        bytes: w4, w5, w6, w7
  ...
  BASE + 0x13C            Word 15       bytes: w60, w61, w62, w63
                                         ↑ 4 INT8 empacotados em 1 word

BASE + 0x500            ACTIVATION      Memória de ativações (8×8 = 64 INT8)
  BASE + 0x500            Word 0        bytes: a0, a1, a2, a3
  ...
  BASE + 0x53C            Word 15       bytes: a60, a61, a62, a63

BASE + 0x900            RESULT          Memória de resultados (8×8 = 64 INT32)
  BASE + 0x900            Word 0        result[0] (INT32 completo)
  BASE + 0x904            Word 1        result[1]
  ...
  BASE + 0x9FC            Word 63       result[63]
                                         ↑ Somente leitura
```

### Exemplo de empacotamento 4×INT8

Para escrever os pesos `[1, 2, 3, 4]` na word 0 da memória de pesos:

```
Word de 32 bits:
┌────────┬────────┬────────┬────────┐
│ byte 3 │ byte 2 │ byte 1 │ byte 0 │
│  w[3]  │  w[2]  │  w[1]  │  w[0]  │
│   4    │   3    │   2    │   1    │
│ 0x04   │ 0x03   │ 0x02   │ 0x01   │
└────────┴────────┴────────┴────────┘
Valor: 0x04030201
```

### Organização na memória

Os 64 valores INT8 são armazenados linearmente. A matriz 8×8 é armazenada **row-major** (linha por linha):

```
Endereço INT8  →  Posição na Matriz
───────────────    ─────────────────
w[0]  →  row=0, col=0
w[1]  →  row=0, col=1
...
w[7]  →  row=0, col=7
w[8]  →  row=1, col=0
...
w[63] →  row=7, col=7
```

Para escrever esses 64 valores, você precisa de apenas **16 acessos de 32 bits** (4 INT8 por word).

---

## 5. Como a Computação Funciona

### Fluxo de dados na Systolic Array

```
              Ativações (horizontal →)
              a0  a1  a2  a3  a4  a5  a6  a7
              │   │   │   │   │   │   │   │
              ▼   ▼   ▼   ▼   ▼   ▼   ▼   ▼
         ┌────┬────┬────┬────┬────┬────┬────┬────┐
   w0 ──▶│ PE │ PE │ PE │ PE │ PE │ PE │ PE │ PE │──▶ psum
   w1 ──▶│ PE │ PE │ PE │ PE │ PE │ PE │ PE │ PE │──▶ psum
   w2 ──▶│ PE │ PE │ PE │ PE │ PE │ PE │ PE │ PE │──▶ psum
   ...    │    │    │    │    │    │    │    │    │
   w7 ──▶│ PE │ PE │ PE │ PE │ PE │ PE │ PE │ PE │──▶ psum
         └────┴────┴────┴────┴────┴────┴────┴────┘
              ▲
              │
         Pesos (pré-carregados em cada PE)
         Modo weight-stationary
```

Cada PE faz: `acumulador = acumulador + (ativação_entrada × peso_local)`

Os resultados (partial sums) descem verticalmente de uma linha para a próxima.

### Máquina de estados do acelerador

```
          ┌──────────┐
          │  S_IDLE  │◀─────────────────────┐
          └────┬─────┘                      │
               │ CTRL[0]=1 (start)          │
               ▼                            │
     ┌─────────────────┐                    │
     │ S_LOAD_WEIGHTS  │ Carrega pesos da   │
     └────────┬────────┘ memória para o    │
              │ array                      │
              ▼                            │
     ┌─────────────────┐                    │
     │  S_LOAD_ACTS    │ Carrega ativações │
     └────────┬────────┘ da memória para   │
              │ o array                   │
              ▼                            │
     ┌─────────────────┐                    │
     │   S_COMPUTE     │ Espera o array    │
     └────────┬────────┘ terminar           │
              │ array_done=1               │
              ▼                            │
     ┌─────────────────┐                    │
     │ S_STORE_RESULTS │ Salva resultados  │
     └────────┬────────┘ na memória        │
              │                            │
              ├─ mais linhas? ──▶ S_LOAD_ACTS
              │
              ▼ (última linha)
     ┌─────────────────┐                    │
     │    S_DONE       │────────────────────┘
     └─────────────────┘ STATUS[1]=done, IRQ
```

### O que a computação faz

A FSM processa a matriz **linha por linha**:

1. **S_LOAD_WEIGHTS**: Carrega a primeira coluna de pesos (8 valores, um por linha) nos PEs
2. **S_LOAD_ACTS**: Carrega uma linha de ativações (8 valores) no array
3. **S_COMPUTE**: O array systolic calcula. Quando termina, salva os 8 resultados parciais
4. **S_STORE_RESULTS**: Avança para a próxima linha e repete a partir de S_LOAD_ACTS

**Atenção**: Esta é uma implementação simplificada. Para uma matriz 8×8 completa, cada linha de resultado requer 8 ciclos de computação (um por coluna de ativação). A FSM atual carrega apenas a primeira coluna de pesos e a primeira linha de ativações — para multiplicação de matrizes completa, seria necessário um loop mais complexo.

---

## 6. Como Integrar no Projeto

### No Quartus (FPGA DE2-115)

Você precisa criar um **módulo top-level** que instancia o NEORV32 e conecta o acelerador:

```vhdl
library ieee;
use ieee.std_logic_1164.all;

library neorv32;
use neorv32.neorv32_package.all;

entity neorv32_system is
  port (
    clk_50MHz : in  std_ulogic;
    rst_n     : in  std_ulogic;
    -- UART para debug
    uart_txd  : out std_ulogic;
    uart_rxd  : in  std_ulogic
  );
end neorv32_system;

architecture rtl of neorv32_system is

  -- Sinais XBUS (Wishbone)
  signal xbus_adr : std_ulogic_vector(31 downto 0);
  signal xbus_dat_out, xbus_dat_in : std_ulogic_vector(31 downto 0);
  signal xbus_we, xbus_stb, xbus_cyc : std_ulogic;
  signal xbus_sel : std_ulogic_vector(3 downto 0);
  signal xbus_ack, xbus_err : std_ulogic;
  signal xbus_cti, xbus_tag : std_ulogic_vector(2 downto 0);

  -- Sinais do acelerador (via gateway)
  signal accel_req : xbus_req_t;
  signal accel_rsp : xbus_rsp_t;
  signal accel_irq : std_ulogic;

begin

  -- ============================================================
  -- NEORV32
  -- ============================================================
  neorv32_inst: entity neorv32.neorv32_top
    generic map (
      CLOCK_FREQUENCY  => 50000000,
      XBUS_EN          => true,        -- Habilita porta externa!
      XBUS_TIMEOUT     => 4096,
      XBUS_REGSTAGE_EN => false,
      IO_UART0_EN      => true,
      IO_UART0_RX_FIFO => 32,
      IO_UART0_TX_FIFO => 32,
      -- ... outros periféricos conforme necessário
      IMEM_EN          => true,
      IMEM_SIZE        => 32*1024,
      DMEM_EN          => true,
      DMEM_SIZE        => 8*1024
    )
    port map (
      clk_i      => clk_50MHz,
      rstn_i     => rst_n,
      -- XBUS → liga nas portas externas
      xbus_adr_o => xbus_adr,
      xbus_dat_o => xbus_dat_out,
      xbus_dat_i => xbus_dat_in,
      xbus_we_o  => xbus_we,
      xbus_sel_o => xbus_sel,
      xbus_stb_o => xbus_stb,
      xbus_cyc_o => xbus_cyc,
      xbus_ack_i => xbus_ack,
      xbus_err_i => xbus_err,
      xbus_cti_o => xbus_cti,
      xbus_tag_o => xbus_tag,
      -- UART
      uart0_txd_o => uart_txd,
      uart0_rxd_i => uart_rxd,
      -- IRQ do acelerador
      irq_mei_i  => accel_irq,
      -- outros sinais...
      cfs_in_i   => (others => '0'),
      cfs_out_o  => open,
      gpio_o     => open,
      gpio_i     => (others => '0')
    );

  -- ============================================================
  -- Gateway: converte sinais escalares em records xbus_req/rsp
  -- ============================================================
  xbus_to_accel: process(xbus_adr, xbus_dat_out, xbus_we,
                         xbus_sel, xbus_stb, xbus_cyc,
                         xbus_cti, xbus_tag, accel_rsp)
  begin
    accel_req.addr <= xbus_adr;
    accel_req.data <= xbus_dat_out;
    accel_req.we   <= xbus_we;
    accel_req.sel  <= xbus_sel;
    accel_req.stb  <= xbus_stb;
    accel_req.cyc  <= xbus_cyc;
    accel_req.cti  <= xbus_cti;
    accel_req.tag  <= xbus_tag;
    xbus_dat_in <= accel_rsp.data;
    xbus_ack    <= accel_rsp.ack;
    xbus_err    <= accel_rsp.err;
  end process;

  -- ============================================================
  -- Acelerador Systolic Array
  -- ============================================================
  accelerator: entity work.neorv32_systolic_wb_accelerator
    port map (
      clk_i    => clk_50MHz,
      rstn_i   => rst_n,
      irq_o    => accel_irq,
      wb_adr_i => accel_req.addr,
      wb_dat_i => accel_req.data,
      wb_dat_o => accel_rsp.data,
      wb_we_i  => accel_req.we,
      wb_sel_i => accel_req.sel,
      wb_stb_i => accel_req.stb,
      wb_cyc_i => accel_req.cyc,
      wb_ack_o => accel_rsp.ack,
      wb_err_o => accel_rsp.err
    );

end rtl;
```

### No Quartus, adicione os arquivos ao projeto:

```
rtl/tcc/tcc_systolic_pe.vhd
rtl/tcc/tcc_systolic_array.vhd
rtl/tcc/tcc_systolic_wb_accelerator.vhd
rtl/core/neorv32_xbus.vhd                    (já existe)
rtl/core/neorv32_bus.vhd                      (já existe)
rtl/core/neorv32_package.vhd                  (já existe)
rtl/core/neorv32_top.vhd                      (já existe)
sim/xbus_gateway.vhd                          (já existe)
seu_top_level.vhd                             (o código acima)
```

---

## 7. Como Usar do Software (C)

### Definição dos registradores

```c
#include <neorv32.h>
#include <stdint.h>

// Endereço base do acelerador no XBUS
// (precisa estar fora do range do IMEM, DMEM e IO do NEORV32)
#define ACCEL_BASE 0x90000000

// Registradores
#define ACCEL_CTRL   (*(volatile uint32_t*)(ACCEL_BASE + 0x000))
#define ACCEL_STATUS (*(volatile uint32_t*)(ACCEL_BASE + 0x004))

// Memórias (acesso por índice de word)
#define ACCEL_WEIGHT(i) (*(volatile uint32_t*)(ACCEL_BASE + 0x100 + ((i)<<2)))
#define ACCEL_ACT(i)    (*(volatile uint32_t*)(ACCEL_BASE + 0x500 + ((i)<<2)))
#define ACCEL_RESULT(i) (*(volatile uint32_t*)(ACCEL_BASE + 0x900 + ((i)<<2)))
```

### Empacotar 4 INT8 em 1 word

```c
// byte 0 = bits [7:0], byte 1 = bits [15:8], etc.
static inline uint32_t pack4(int8_t b0, int8_t b1, int8_t b2, int8_t b3) {
    return ((uint32_t)(uint8_t)b0)       |
           ((uint32_t)(uint8_t)b1 << 8)  |
           ((uint32_t)(uint8_t)b2 << 16) |
           ((uint32_t)(uint8_t)b3 << 24);
}
```

### Exemplo completo: multiplicar por matriz identidade

```c
int main(void) {
    neorv32_uart0_setup(19200, 0);

    // 1. Limpar o acelerador
    ACCEL_CTRL = 0x00000002;          // bit [1] = clear
    while (ACCEL_STATUS & 0x01);      // esperar busy=0

    // 2. Escrever pesos (matriz identidade 8×8)
    //    Linha i tem 1 na coluna i, 0 nas demais
    for (int row = 0; row < 8; row++) {
        int word_idx = row / 4;       // qual word de 32 bits
        int byte_pos = row % 4;       // qual byte dentro da word

        uint32_t w = 0;
        if (byte_pos == 0) w |= 0x00000001;
        if (byte_pos == 1) w |= 0x00000100;
        if (byte_pos == 2) w |= 0x00010000;
        if (byte_pos == 3) w |= 0x01000000;
        ACCEL_WEIGHT(word_idx) = w;
    }

    // 3. Escrever ativações (todas = 1)
    for (int i = 0; i < 16; i++) {
        ACCEL_ACT(i) = pack4(1, 1, 1, 1);
    }

    // 4. Iniciar computação
    ACCEL_CTRL = 0x00000001;          // bit [0] = start

    // 5. Esperar terminar
    while (!(ACCEL_STATUS & 0x02));   // esperar done=1

    // 6. Ler resultados
    for (int i = 0; i < 64; i++) {
        neorv32_uart0_printf("result[%d] = %d\n",
                             i, (int32_t)ACCEL_RESULT(i));
    }

    return 0;
}
```

---

## 8. Como Testar

### Pré-requisito: instalar GHDL

```bash
# Ubuntu/Debian
sudo apt install ghdl

# macOS (com Homebrew)
brew install ghdl

# Verificar
ghdl --version
```

### Teste 1: Standalone (só o acelerador, sem NEORV32)

Testa a interface Wishbone diretamente, sem precisar de toolchain RISC-V:

```bash
cd /home/levi/neorv32
bash sim/tcc/run_accel_sim.sh
```

Saída esperada:
```
[NOTE] === TEST 1: Register R/W ===
[NOTE] [PASS] CTRL write/read
[NOTE] [PASS] STATUS idle (busy=0, done=0)
...
[NOTE] ALL TESTS PASSED
```

### Teste 2: Integrado com NEORV32 (CPU + acelerador)

Requer toolchain RISC-V (`riscv-none-elf-gcc` ou `riscv64-unknown-elf-gcc`):

```bash
# 1. Compilar firmware
cd /home/levi/neorv32/sw/tcc/test_systolic_accel
make clean_all
make USER_FLAGS+="-DUART0_SIM_MODE"

# 2. Copiar imagem para o diretório RTL
make install

# 3. Rodar simulação com testbench integrado
cd /home/levi/neorv32
bash sim/tcc/run_accel_sim.sh neorv32_systolic_tb
```

### Teste 3: Na FPGA (hardware real)

1. Adicione os arquivos VHDL ao projeto Quartus
2. Crie o top-level conforme a seção 6
3. Compile o firmware C com `make flash` (ou `make upload`)
4. Conecte o UART e observe a saída

---

## 9. Resumo dos Arquivos

```
rtl/core/
├── tcc_systolic_pe.vhd              ← PE individual (multiply + accumulate)
├── tcc_systolic_array.vhd           ← Array 8×8 de PEs
├── tcc_systolic_wb_accelerator.vhd  ← Interface Wishbone + FSM + memórias
├── neorv32_systolic_accelator.vhd       ← VERSÃO ANTIGA (CFS) — não usar
│
sim/
├── tcc_systolic_wb_accelerator_tb.vhd ← Testbench standalone
├── tcc_systolic_tb.vhd                ← Testbench integrado com NEORV32
├── run_accel_sim.sh                       ← Script para rodar simulação
├── xbus_gateway.vhd                       ← Decodificador de endereço XBUS
│
sw/tcc/test_systolic_accel/
├── main.c     ← Programa de teste em C
├── makefile   ← Build do firmware
```
