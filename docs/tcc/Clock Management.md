# Clock Management - Gestão de Clock e Desempenho

> **Otimização de Frequência e Throughput no Cyclone IV E**

---

## 📋 Visão Geral

A placa [[DE2-115 Board|DE2-115]] opera com um oscilador base de **50MHz**. No entanto, este não é o limite de velocidade do projeto. Com o uso adequado de PLLs e técnicas de otimização, é possível alcançar frequências significativamente maiores.

### 🔗 Links Relacionados
- [[Home]] - Página principal
- [[DE2-115 Board]] - Especificações da placa
- [[Performance Metrics]] - Métricas de desempenho

---

## ⏰ Clock Base da DE2-115

### Especificações do Oscilador

| Parâmetro | Valor |
|-----------|-------|
| **Frequência Base** | 50 MHz |
| **Tipo** | Cristal oscilador |
| **Estabilidade** | ±50 ppm |
| **Tensão** | 3.3V |

### Limitações do Clock Base

```
┌─────────────────────────────────────────────────────────────┐
│           Clock de 50 MHz - Limitações                       │
│                                                              │
│  ┌─────────────────────────────────────────────────────┐   │
│  │  Throughput Teórico                                   │   │
│  │                                                       │   │
│  │  • Operações por segundo: 50M ops                    │   │
│  │  • Convoluções pequenas: ~100K/s                     │   │
│  │  • Inferência CNN simples: ~10-50/s                  │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                              │
│  ┌─────────────────────────────────────────────────────┐   │
│  │  Gargalos                                             │   │
│  │                                                       │   │
│  │  • Baixo paralelismo efetivo                         │   │
│  │  • Memória subutilizada                              │   │
│  │  • Performance limitada                              │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

---

## 🔧 PLLs (Phase-Locked Loops)

### Recursos do Cyclone IV E

O FPGA Cyclone IV E possui **4 PLLs internos** que podem ser configurados para gerar clocks de frequências mais altas.

### Especificações das PLLs

| Parâmetro | Valor |
|-----------|-------|
| **Número de PLLs** | 4 |
| **Frequência de Entrada** | 5-500 MHz |
| **Frequência de Saída** | Até 472 MHz (teórico) |
| **Multiplicador** | 1-32 |
| **Divisor** | 1-32 |

### Configuração de PLL

```verilog
// Exemplo de configuração de PLL para 100MHz
pll_100mhz u_pll (
    .inclk0  (clk_50mhz),    // Input: 50 MHz
    .c0      (clk_100mhz),   // Output: 100 MHz
    .c1      (clk_120mhz),   // Output: 120 MHz
    .locked  (pll_locked)    // Status
);
```

---

## 📈 Frequências de Operação

### Faixas de Frequência Recomendadas

| Frequência | Aplicação | Dificuldade |
|------------|-----------|-------------|
| **50 MHz** | Desenvolvimento e debug | Fácil |
| **100 MHz** | Operação padrão | Moderada |
| **120 MHz** | Alta performance | Moderada |
| **150+ MHz** | Máxima performance | Difícil |

### Frequência Recomendada para o TCC

**100 MHz** é a frequência recomendada por oferecer:
- ✅ Equilíbrio entre performance e facilidade de timing closure
- ✅ Dobro da velocidade base
- ✅ Boa margem de segurança
- ✅ Compatível com a maioria dos periféricos

---

## 🚀 Throughput e Performance

### Cálculo de Throughput

Para uma **Matriz Sistólica 8x8** operando a diferentes frequências:

```
┌─────────────────────────────────────────────────────────────┐
│           Cálculo de Throughput                              │
│                                                              │
│  Matriz Sistólica 8x8 = 64 MACs (Multiply-Accumulate)       │
│                                                              │
│  Operações por ciclo: 64 (1 MAC por PE por ciclo)           │
│                                                              │
│  ┌─────────────────────────────────────────────────────┐   │
│  │  Frequência    │  Throughput (GOPS)                 │   │
│  ├─────────────────────────────────────────────────────┤   │
│  │  50 MHz        │  3.2 GOPS                          │   │
│  │  100 MHz       │  6.4 GOPS                          │   │
│  │  120 MHz       │  7.68 GOPS                         │   │
│  │  150 MHz       │  9.6 GOPS                          │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                              │
│  GOPS = Giga Operations Per Second                          │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### Throughput Máximo (120 MHz)

| Métrica | Valor |
|---------|-------|
| **Frequência** | 120 MHz |
| **MACs paralelos** | 64 |
| **Throughput** | **59.52 GOPS** |
| **Speedup vs Software** | ~350% |

---

## ⚠️ Gargalo de Memória

### O Principal Desafio

O principal desafio a 50MHz ou 120MHz será a **latência da memória SDRAM externa**.

### Características da SDRAM

| Parâmetro | Valor |
|-----------|-------|
| **Tamanho** | 128 MB |
| **Tipo** | DDR2 SDRAM |
| **Latência de Acesso** | ~50-100 ns |
| **Largura de Banda** | ~3.2 GB/s (teórico) |

### Técnicas de Mitigação

#### 1. Buffers Duplos (Ping-Pong)

```
┌─────────────────────────────────────────────────────────────┐
│           Buffer Ping-Pong                                    │
│                                                              │
│         ┌─────────────┐         ┌─────────────┐            │
│         │   Buffer A  │         │   Buffer B  │            │
│         │   (Ping)    │         │   (Pong)    │            │
│         └──────┬──────┘         └──────┬──────┘            │
│                │                       │                    │
│     ┌──────────┴──────────┐   ┌───────┴────────┐           │
│     │                     │   │                │           │
│     ▼                     ▼   ▼                ▼           │
│  ┌─────────────┐    ┌─────────────┐    ┌─────────────┐    │
│  │   Acelerador │◀──│   Troca de  │──▶│   Carrega   │    │
│  │   Processa A │    │   Buffers   │    │   Buffer B  │    │
│  └─────────────┘    └─────────────┘    └─────────────┘    │
│                                                              │
│  Enquanto o acelerador processa um buffer,                   │
│  o DMA carrega o outro da SDRAM                             │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

#### 2. Tiling (Blocagem)

```
┌─────────────────────────────────────────────────────────────┐
│           Tiling de Dados                                    │
│                                                              │
│  Imagem Grande (não cabe na memória interna)                │
│  ┌────────────────────────────────────────────┐            │
│  │  ┌─────┬─────┬─────┬─────┐                 │            │
│  │  │ T1  │ T2  │ T3  │ T4  │                 │            │
│  │  ├─────┼─────┼─────┼─────┤                 │            │
│  │  │ T5  │ T6  │ T7  │ T8  │                 │            │
│  │  ├─────┼─────┼─────┼─────┤                 │            │
│  │  │ T9  │ T10 │ T11 │ T12 │                 │            │
│  │  └─────┴─────┴─────┴─────┘                 │            │
│  └────────────────────────────────────────────┘            │
│                                                              │
│  Cada tile (T1-T12) cabe na memória M9K interna             │
│  Processa um tile por vez                                    │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

#### 3. Prefetching

- Carregar dados antes de serem necessários
- Usar DMA para transferências em background
- Esconder latência com computação sobreposta

---

## 📊 Domínios de Clock

### Arquitetura Multi-Clock

```
┌─────────────────────────────────────────────────────────────┐
│           Domínios de Clock do Sistema                       │
│                                                              │
│  ┌─────────────────────────────────────────────────────┐   │
│  │  Domínio 1: 50 MHz (Periféricos)                     │   │
│  │  • UART, SPI, I2C                                    │   │
│  │  • GPIO, Switches, LEDs                              │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                              │
│  ┌─────────────────────────────────────────────────────┐   │
│  │  Domínio 2: 100 MHz (NEORV32 + Memória)              │   │
│  │  • CPU de controle                                   │   │
│  │  • Controlador SDRAM                                 │   │
│  │  • Barramento do sistema                             │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                              │
│  ┌─────────────────────────────────────────────────────┐   │
│  │  Domínio 3: 100-120 MHz (Acelerador)                 │   │
│  │  • Matriz Sistólica                                  │   │
│  │  • Memórias M9K                                      │   │
│  │  • DSP Blocks                                        │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                              │
│  ┌─────────────────────────────────────────────────────┐   │
│  │  Domínio 4: 25-50 MHz (VGA/LCD)                      │   │
│  │  • Controlador de display                            │   │
│  │  • Framebuffer                                       │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### Sincronização entre Domínios

| Técnica | Aplicação |
|---------|-----------|
| **FIFOs** | Transferência de dados entre domínios |
| **Handshake** | Sincronização de eventos |
| **Dual-port RAM** | Compartilhamento de memória |
| **Clock Domain Crossing (CDC)** | Metodologia geral |

---

## 🔍 Timing Closure

### Desafios

- **Setup Time**: Dados devem estar estáveis antes do clock
- **Hold Time**: Dados devem permanecer estáveis após o clock
- **Clock Skew**: Variação no tempo de chegada do clock

### Estratégias de Otimização

1. **Pipelining**: Dividir operações longas em estágios
2. **Retiming**: Mover registradores para equilibrar caminhos
3. **Logic Duplication**: Reduzir fan-out
4. **Floorplanning**: Posicionar blocos estrategicamente

### Verificação no Quartus

```
TimeQuest Timing Analyzer
├── Setup Slack: Deve ser positivo
├── Hold Slack: Deve ser positivo
├── Clock Skew: Minimizar
└── Max Frequency: Verificar se atende requisito
```

---

## 📚 Referências

- [Cyclone IV Device Datasheet](https://www.intel.com/content/www/us/en/docs/programmable/149814/current/overview.html)
- [Terasic DE2-115 User Manual](https://www.terasic.com.tw/cgi-bin/page/archive.pl?Language=English&CategoryNo=139&No=502)
- [TimeQuest Timing Analyzer User Guide](https://www.intel.com/content/www/us/en/docs/programmable/683426/current/overview.html)

---

## 🏷️ Tags

#ClockManagement #PLL #Timing #Throughput #GOPS #SDRAM #TimingClosure #Performance

---

**Veja também:**
- [[DE2-115 Board]] - Especificações da placa
- [[Systolic Array]] - Arquitetura do acelerador
- [[Memory Management]] - Gestão de memória e buffers
- [[Performance Metrics]] - Métricas de desempenho
