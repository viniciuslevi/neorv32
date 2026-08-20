# Implementation Matrix - Matriz de Implementação

> **Visão Geral das Tecnologias Recomendadas para o TCC**

---

## 📋 Visão Geral

Esta nota apresenta a matriz de implementação recomendada para o projeto de aceleração de redes neurais no FPGA Cyclone IV E. Cada componente foi selecionado considerando viabilidade técnica, valor acadêmico e recursos disponíveis.

### 🔗 Links Relacionados
- [[Home]] - Página principal
- [[NEORV32]] - CPU de controle
- [[Systolic Array]] - Acelerador de IA
- [[HLS Design Flow]] - Fluxo de design

---

## 📊 Matriz de Implementação

### Visão Geral

| Componente | Tecnologia Sugerida | Justificativa |
|------------|---------------------|---------------|
| **CPU de Controle** | NEORV32 (RV32IM) | Baixo consumo de área e excelente documentação |
| **Acelerador IA** | Matriz Sistólica 8x8 (INT8) | Mapeamento ideal nos 266 blocos DSP da placa |
| **Barramento** | Wishbone com wrapper Avalon | Compatibilidade com o ecossistema Terasic/Intel |
| **Fluxo de Design** | Python (Treino) → hls4ml ou C++ HLS | Substitui a ausência do AI Suite para chips antigos |
| **Clock Final** | 100MHz (via PLL) | Equilíbrio entre performance e facilidade de timing closure |

---

## 🏗️ Arquitetura Completa

```
┌─────────────────────────────────────────────────────────────────────────┐
│                    SISTEMA COMPLETO - FPGA Cyclone IV E                  │
│                                                                          │
│  ┌────────────────────────────────────────────────────────────────────┐ │
│  │                      DOMÍNIO DE CONTROLE                            │ │
│  │                                                                     │ │
│  │  ┌──────────────────────────────────────────────────────────────┐  │ │
│  │  │                    NEORV32 (RV32IM)                          │  │ │
│  │  │                                                              │  │ │
│  │  │  • ~2,300 LUTs (<5% do chip)                                │  │ │
│  │  │  • Gerenciamento de memória                                  │  │ │
│  │  │  • Controle do acelerador                                    │  │ │
│  │  │  • Coleta de resultados                                      │  │ │
│  │  └──────────────────────────────────────────────────────────────┘  │ │
│  │                              │                                     │ │
│  │              ┌───────────────┴───────────────┐                    │ │
│  │              │    Wishbone + Avalon Wrapper   │                    │ │
│  │              └───────────────┬───────────────┘                    │ │
│  └──────────────────────────────┼─────────────────────────────────────┘ │
│                                 │                                        │
│  ┌──────────────────────────────┼─────────────────────────────────────┐ │
│  │                      DOMÍNIO DE CÁLCULO           │                │ │
│  │                              │                    │                │ │
│  │  ┌───────────────────────────┴───────────────┐   │                │ │
│  │  │          MATRIZ SISTÓLICA 8x8 (INT8)       │   │                │ │
│  │  │                                             │   │                │ │
│  │  │  • 64 Processing Elements (PEs)            │   │                │ │
│  │  │  • 266 DSP Blocks utilizados               │   │                │ │
│  │  │  • >95% dos recursos do chip               │   │                │ │
│  │  │  • Throughput: até 59.52 GOPS @ 120MHz     │   │                │ │
│  │  └───────────────────────────────────────────┘   │                │ │
│  │                              │                    │                │ │
│  └──────────────────────────────┼─────────────────────────────────────┘ │
│                                 │                                        │
│  ┌──────────────────────────────┼─────────────────────────────────────┐ │
│  │                      DOMÍNIO DE MEMÓRIA           │                │ │
│  │                              │                    │                │ │
│  │  ┌───────────────────────────┴───────────────┐   │                │ │
│  │  │          MEMÓRIA E ARMAZENAMENTO           │   │                │ │
│  │  │                                             │   │                │ │
│  │  │  • SDRAM 128MB (dados e pesos)            │   │                │ │
│  │  │  • M9K Blocks (buffers internos)           │   │                │ │
│  │  │  • Flash (bitstream e programa)            │   │                │ │
│  │  └───────────────────────────────────────────┘   │                │ │
│  │                                                   │                │ │
│  └───────────────────────────────────────────────────┼────────────────┘ │
│                                                      │                  │
│  ┌───────────────────────────────────────────────────┼────────────────┐ │
│  │                      PERIFÉRICOS                   │                │ │
│  │                                                    │                │ │
│  │  ┌─────────────┐  ┌─────────────┐  ┌───────────┐ │                │ │
│  │  │    VGA/     │  │    UART     │  │   GPIO    │ │                │ │
│  │  │    LCD      │  │  (Debug)    │  │ (Switches)│ │                │ │
│  │  └─────────────┘  └─────────────┘  └───────────┘ │                │ │
│  │                                                    │                │ │
│  └────────────────────────────────────────────────────┼────────────────┘ │
│                                                       │                  │
└───────────────────────────────────────────────────────┼──────────────────┘
                                                        │
                                              ┌─────────┴─────────┐
                                              │    CLOCK: 100MHz   │
                                              │    (via PLL)       │
                                              └────────────────────┘
```

---

## 🔧 Detalhamento dos Componentes

### 1. CPU de Controle: NEORV32 (RV32IM)

#### Especificações

| Parâmetro | Valor |
|-----------|-------|
| **Arquitetura** | RISC-V 32-bit |
| **Extensões** | I (Integer), M (Multiplication) |
| **LUTs** | ~2,300 |
| **Frequência** | Até 100 MHz |
| **Interface** | Wishbone |

#### Responsabilidades

- ✅ Carregar pesos da SDRAM para M9K
- ✅ Iniciar processamento do acelerador
- ✅ Coletar resultados para exibição
- ✅ Pré-processamento (normalização)

**Veja mais em:** [[NEORV32]]

---

### 2. Acelerador IA: Matriz Sistólica 8x8 (INT8)

#### Especificações

| Parâmetro | Valor |
|-----------|-------|
| **Dimensões** | 8x8 (64 PEs) |
| **Precisão** | INT8 (8-bit integer) |
| **DSP Blocks** | 266 |
| **LUTs** | ~50,000 (estimado) |
| **Throughput** | 6.4 GOPS @ 100MHz |

#### Operações Suportadas

- ✅ Convoluções 2D
- ✅ Multiplicação de matrizes
- ✅ Ativações (ReLU, etc.)
- ✅ Pooling

**Veja mais em:** [[Systolic Array]]

---

### 3. Barramento: Wishbone + Avalon

#### Especificações

| Parâmetro | Valor |
|-----------|-------|
| **Protocolo Principal** | Wishbone |
| **Wrapper** | Avalon-MM |
| **Largura de Dados** | 32-bit |
| **Endereçamento** | Memory-mapped |

#### Vantagens

- ✅ Compatível com NEORV32 nativo
- ✅ Integração com IPs Intel via Qsys
- ✅ Suporte a DMA

**Veja mais em:** [[Bus Integration]]

---

### 4. Fluxo de Design: Python → HLS

#### Pipeline

```
┌─────────────────────────────────────────────────────────────┐
│                    FLUXO DE DESIGN                           │
│                                                              │
│  Fase 1          Fase 2           Fase 3          Fase 4   │
│  ┌─────────┐     ┌─────────┐      ┌─────────┐     ┌───────┐│
│  │ Treino  │ ──▶ │ Conversão│ ──▶ │ Síntese │ ──▶ │ Teste ││
│  │         │     │         │      │         │     │       ││
│  │ Python  │     │ hls4ml  │      │ Quartus │     │ DE2   ││
│  │ Keras   │     │ ou HLS  │      │ Prime   │     │ -115  ││
│  │ PyTorch │     │         │      │         │     │       ││
│  └─────────┘     └─────────┘      └─────────┘     └───────┘│
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

#### Ferramentas

| Fase | Ferramenta |
|------|------------|
| **Treino** | Python + TensorFlow/Keras ou PyTorch |
| **Conversão** | hls4ml ou Intel HLS Compiler |
| **Síntese** | Quartus Prime + Platform Designer |
| **Teste** | DE2-115 + SignalTap/ChipScope |

**Veja mais em:** [[HLS Design Flow]]

---

### 5. Clock: 100MHz via PLL

#### Especificações

| Parâmetro | Valor |
|-----------|-------|
| **Clock Base** | 50 MHz |
| **Clock Final** | 100 MHz |
| **Método** | PLL interno |
| **Speedup** | 2x |

#### Configuração

```verilog
// PLL Configuration
pll_system u_pll (
    .inclk0  (clk_50mhz),    // Input: 50 MHz
    .c0      (clk_100mhz),   // Output: 100 MHz (sistema)
    .c1      (clk_50mhz),    // Output: 50 MHz (periféricos)
    .locked  (pll_locked)    // Status
);
```

**Veja mais em:** [[Clock Management]]

---

## 📈 Estimativas de Recursos

### Utilização do Cyclone IV E (EP4CE115)

| Recurso | Disponível | Utilizado | Porcentagem |
|---------|------------|-----------|-------------|
| **LUTs** | 114,480 | ~55,000 | ~48% |
| **Registers** | 114,480 | ~30,000 | ~26% |
| **M9K Blocks** | 432 | ~200 | ~46% |
| **DSP Blocks** | 266 | ~200 | ~75% |
| **PLLs** | 4 | 1 | 25% |

### Distribuição por Componente

```
┌─────────────────────────────────────────────────────────────┐
│           Distribuição de Recursos                           │
│                                                              │
│  NEORV32 (CPU)                                               │
│  ████████░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░ 2,300 LUTs  │
│                                                              │
│  Matriz Sistólica (Acelerador)                              │
│  ██████████████████████████████████████████████ ~50K LUTs  │
│                                                              │
│  Buffers e Periféricos                                       │
│  ████████░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░ ~3K LUTs    │
│                                                              │
│  Disponível                                                  │
│  ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░ ~54K LUTs    │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

---

## 🎯 Métricas de Desempenho Esperadas

### Throughput

| Métrica | Valor |
|---------|-------|
| **GOPS @ 100MHz** | 6.4 GOPS |
| **GOPS @ 120MHz** | 7.68 GOPS |
| **Speedup vs Software** | ~350% |

### Latência

| Operação | Latência Estimada |
|----------|-------------------|
| **Convolução 3x3** | ~100 ciclos |
| **Inferência CNN simples** | ~10,000 ciclos |
| **Transferência SDRAM** | ~1,000 ciclos |

### Eficiência

| Métrica | Valor |
|---------|-------|
| **Eficiência DSP** | ~75% |
| **Eficiência de Memória** | ~80% |
| **Utilização de LUTs** | ~48% |

---

## ✅ Checklist de Implementação

### Fase 1: Preparação
- [ ] Configurar ambiente Quartus Prime
- [ ] Instalar NEORV32
- [ ] Configurar hls4ml ou HLS Compiler

### Fase 2: CPU de Controle
- [ ] Sintetizar NEORV32
- [ ] Configurar Wishbone wrapper
- [ ] Testar comunicação básica

### Fase 3: Acelerador
- [ ] Desenvolver matriz sistólica
- [ ] Integrar com DSP blocks
- [ ] Testar operações MAC

### Fase 4: Integração
- [ ] Conectar CPU e acelerador
- [ ] Configurar controlador SDRAM
- [ ] Implementar buffers ping-pong

### Fase 5: Software
- [ ] Desenvolver firmware NEORV32
- [ ] Implementar driver do acelerador
- [ ] Criar interface de usuário

### Fase 6: Validação
- [ ] Testes funcionais
- [ ] Análise de timing
- [ ] Medição de performance

---

## 🏷️ Tags

#ImplementationMatrix #Architecture #NEORV32 #SystolicArray #SystemDesign #CycloneIV

---

**Veja também:**
- [[Home]] - Página principal
- [[NEORV32]] - CPU de controle
- [[Systolic Array]] - Acelerador de IA
- [[Bus Integration]] - Integração de barramento
- [[Clock Management]] - Gestão de clock
- [[HLS Design Flow]] - Fluxo de design
