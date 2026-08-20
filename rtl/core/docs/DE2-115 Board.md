# DE2-115 Board - Especificações da Placa de Desenvolvimento

> **Terasic DE2-115 com FPGA Cyclone IV E (EP4CE115)**

---

## 📋 Visão Geral

A **DE2-115** é uma placa de desenvolvimento educacional e profissional da Terasic, baseada no FPGA **Cyclone IV E** (modelo EP4CE115). É amplamente utilizada em ambientes acadêmicos para ensino de design digital e sistemas embarcados.

### 🔗 Links Relacionados
- [[Home]] - Página principal
- [[Clock Management]] - Gestão de clock
- [[Implementation Matrix]] - Matriz de implementação

---

## 🔧 FPGA Principal: Cyclone IV E

### Especificações do EP4CE115F29C7

| Parâmetro | Valor |
|-----------|-------|
| **Família** | Cyclone IV E |
| **Modelo** | EP4CE115F29C7 |
| **Pacote** | 780-pin FBGA |
| **LUTs** | 114,480 |
| **Registers** | 114,480 |
| **M9K Memory Blocks** | 432 |
| **Memória Total (M9K)** | 3,888 Kb |
| **DSP Blocks** | 266 |
| **PLLs** | 4 |
| **I/Os** | 528 |

### Recursos de Memória

```
┌─────────────────────────────────────────────────────────────┐
│           RECURSOS DE MEMÓRIA DO CYCLONE IV E                │
│                                                              │
│  M9K Blocks                                                  │
│  ┌─────────────────────────────────────────────────────┐   │
│  │  Total: 432 blocos                                   │   │
│  │  Cada bloco: 9,216 bits (1,152 bytes)               │   │
│  │  Total: 3,888 Kb (~486 KB)                          │   │
│  │                                                      │   │
│  │  Configurações possíveis:                            │   │
│  │  • 8192 × 1 bit                                     │   │
│  │  • 4096 × 2 bits                                    │   │
│  │  • 2048 × 4 bits                                    │   │
│  │  • 1024 × 8 bits (mais comum)                       │   │
│  │  • 512 × 16 bits                                    │   │
│  │  • 256 × 32 bits                                    │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                              │
│  DSP Blocks                                                  │
│  ┌─────────────────────────────────────────────────────┐   │
│  │  Total: 266 blocos                                   │   │
│  │  Cada bloco: 18×18 multiplicador                    │   │
│  │  Ou: 2× 9×9 multiplicadores                         │   │
│  │  Com acumulador de 64 bits                          │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

---

## 📦 Periféricos da Placa

### Memória Externa

| Tipo        | Capacidade | Descrição           |
| ----------- | ---------- | ------------------- |
| **SDRAM**   | 128 MB     | DDR2 SDRAM          |
| **SRAM**    | 2 MB       | Static RAM          |
| **Flash**   | 8 MB       | NOR Flash           |
| **SD Card** | -          | Slot para cartão SD |

### Displays

| Tipo | Especificação |
|------|---------------|
| **LCD** | 16×2 caracteres |
| **VGA** | Conector DB15 |
| **7-Segment** | 8 displays |
| **LEDs** | 18 LEDs verdes + 9 LEDs vermelhos |

### Conectores de Expansão

| Conector | Função |
|----------|--------|
| **GPIO 0** | 36-pin expansion header |
| **GPIO 1** | 36-pin expansion header |
| **HSMC** | High-Speed Mezzanine Card |
| **HDMI** | Tx/Rx |

### Comunicação

| Interface | Descrição |
|-----------|-----------|
| **USB** | USB Blaster (programação) + USB 2.0 |
| **Ethernet** | 10/100/1000 Mbps |
| **RS-232** | Serial UART |
| **PS/2** | Teclado/Mouse |
| **IR** | Infravermelho |

### Entrada do Usuário

| Componente | Quantidade |
|------------|------------|
| **Switches** | 18 |
| **Pushbuttons** | 4 |
| **Clock** | 50 MHz oscillator |

---

## ⏰ Clock e Reset

### Clock de 50 MHz

```
┌─────────────────────────────────────────────────────────────┐
│           SISTEMA DE CLOCK                                   │
│                                                              │
│  Oscilador Externo                                           │
│  ┌─────────────┐                                            │
│  │   50 MHz    │───────────────────────────────▶ CLK_50MHz  │
│  │  Oscillator │                                             │
│  └─────────────┘                                            │
│         │                                                    │
│         ▼                                                    │
│  ┌─────────────┐                                            │
│  │    PLL      │                                            │
│  │  (Interno)  │───┬───▶ CLK_100MHz                         │
│  └─────────────┘   ├───▶ CLK_120MHz                         │
│                    └───▶ CLK_25MHz (VGA)                     │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### PLLs Disponíveis

| PLL | Uso Típico |
|-----|------------|
| **PLL_1** | Sistema principal (100 MHz) |
| **PLL_2** | Memória SDRAM |
| **PLL_3** | Display VGA |
| **PLL_4** | Disponível |

---

## 🔌 Pinagem Importante

### Clock e Reset

| Sinal | Pino | Função |
|-------|------|--------|
| `CLOCK_50` | PIN_Y2 | Clock principal 50 MHz |
| `CLOCK2_50` | PIN_AG14 | Clock secundário |
| `CLOCK3_50` | PIN_AG15 | Clock terciário |
| `KEY[0]` | PIN_M23 | Reset (pushbutton) |

### LEDs (Debug)

| Sinal | Pino | Função |
|-------|------|--------|
| `LEDG[0]` | PIN_E21 | LED verde 0 |
| `LEDG[1]` | PIN_E22 | LED verde 1 |
| ... | ... | ... |
| `LEDR[0]` | PIN_G19 | LED vermelho 0 |

### UART

| Sinal | Pino | Função |
|-------|------|--------|
| `UART_RXD` | PIN_G12 | Recepção serial |
| `UART_TXD` | PIN_G9 | Transmissão serial |

### SDRAM

| Sinal | Função |
|-------|--------|
| `DRAM_ADDR[12:0]` | Endereço |
| `DRAM_BA[1:0]` | Bank address |
| `DRAM_CAS_N` | CAS strobe |
| `DRAM_CKE` | Clock enable |
| `DRAM_CLK` | Clock |
| `DRAM_CS_N` | Chip select |
| `DRAM_DQ[31:0]` | Data |
| `DRAM_DQM[3:0]` | Data mask |
| `DRAM_RAS_N` | RAS strobe |
| `DRAM_WE_N` | Write enable |

---

## 📊 Consumo de Energia

### Fontes de Alimentação

| Tensão | Uso |
|--------|-----|
| **3.3V** | I/O e periféricos |
| **2.5V** | DDR2 SDRAM |
| **1.2V** | Core do FPGA |

### Consumo Estimado

| Cenário | Consumo |
|---------|---------|
| **Idle** | ~2W |
| **Médio** | ~5W |
| **Máximo** | ~10W |

---

## 🛠️ Ferramentas de Desenvolvimento

### Software Necessário

| Ferramenta | Versão | Função |
|------------|--------|--------|
| **Quartus Prime** | 20.1+ | Síntese e programação |
| **ModelSim** | 20.1+ | Simulação |
| **Platform Designer** | Incluso | Integração de IPs |
| **USB Blaster Driver** | - | Programação via USB |

### Fluxo de Programação

```
┌─────────────────────────────────────────────────────────────┐
│           FLUXO DE PROGRAMAÇÃO                               │
│                                                              │
│  1. Conectar USB Blaster                                     │
│     └── Cabo USB da placa ao PC                              │
│                                                              │
│  2. Ligar a placa                                            │
│     └── Switch ON na placa                                   │
│                                                              │
│  3. Abrir Quartus Programmer                                 │
│     └── Tools → Programmer                                   │
│                                                              │
│  4. Configurar Hardware                                      │
│     └── Hardware Setup → USB-Blaster                         │
│                                                              │
│  5. Adicionar arquivo .sof                                   │
│     └── Add File → projeto.sof                               │
│                                                              │
│  6. Programar                                                │
│     └── Start                                                │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

---

## 📐 Diagrama de Blocos

```
┌─────────────────────────────────────────────────────────────────────────┐
│                    DE2-115 BOARD                                         │
│                                                                          │
│  ┌────────────────────────────────────────────────────────────────────┐ │
│  │                    CYCLONE IV E FPGA                                │ │
│  │                                                                     │ │
│  │  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐            │ │
│  │  │   Logic      │  │   Memory     │  │    DSP       │            │ │
│  │  │  114K LUTs   │  │  432 M9K     │  │  266 Blocks  │            │ │
│  │  └──────────────┘  └──────────────┘  └──────────────┘            │ │
│  │                                                                     │ │
│  │  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐            │ │
│  │  │    PLLs      │  │     I/O      │  │   JTAG       │            │ │
│  │  │     4        │  │    528       │  │  (USB Blaster)│            │ │
│  │  └──────────────┘  └──────────────┘  └──────────────┘            │ │
│  └────────────────────────────────────────────────────────────────────┘ │
│                              │                                           │
│         ┌────────────────────┼────────────────────┐                     │
│         │                    │                    │                     │
│         ▼                    ▼                    ▼                     │
│  ┌─────────────┐    ┌─────────────────┐    ┌─────────────┐            │
│  │   Memória   │    │   Periféricos   │    │ Conectores  │            │
│  │             │    │                 │    │             │            │
│  │ • 128MB DDR2│    │ • VGA           │    │ • GPIO      │            │
│  │ • 2MB SRAM  │    │ • LCD 16×2      │    │ • HSMC      │            │
│  │ • 8MB Flash │    │ • 8× 7-Seg      │    │ • HDMI      │            │
│  │ • SD Card   │    │ • 18 LEDs       │    │ • Ethernet  │            │
│  │             │    │ • 18 Switches   │    │ • USB       │            │
│  │             │    │ • 4 Buttons     │    │ • RS-232    │            │
│  └─────────────┘    └─────────────────┘    └─────────────┘            │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## 📚 Recursos e Documentação

### Manuais Oficiais

- [DE2-115 User Manual](https://www.terasic.com.tw/cgi-bin/page/archive.pl?Language=English&CategoryNo=139&No=502)
- [DE2-115 Schematic](https://www.terasic.com.tw/cgi-bin/page/archive.pl?Language=English&CategoryNo=139&No=502&PartNo=4)
- [Cyclone IV Device Handbook](https://www.intel.com/content/www/us/en/docs/programmable/149814/current/overview.html)

### Tutoriais

- [Terasic DE2-115 Tutorials](https://www.terasic.com.tw/cgi-bin/page/archive.pl?Language=English&CategoryNo=139&No=502&PartNo=7)
- [Intel FPGA Documentation](https://www.intel.com/content/www/us/en/docs/programmable/149814/current/overview.html)

---

## 🏷️ Tags

#DE2-115 #CycloneIV #Terasic #FPGA #Hardware #DevelopmentBoard #EP4CE115

---

**Veja também:**
- [[Home]] - Página principal
- [[Clock Management]] - Gestão de clock
- [[Implementation Matrix]] - Recursos disponíveis
- [[NEORV32]] - CPU de controle
