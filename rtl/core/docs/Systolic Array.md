# Systolic Array - Matriz Sistólica

> **Acelerador de Redes Neurais com Matriz Sistólica 8x8**

---

## 📋 Visão Geral

A **Matriz Sistólica** é a arquitetura escolhida para o acelerador de IA no Cyclone IV E. Esta estrutura permite processamento paralelo massivo de operações de multiplicação-acumulação (MAC), fundamentais para redes neurais convolucionais.

### 🔗 Links Relacionados
- [[Home]] - Página principal
- [[Implementation Matrix]] - Visão geral da implementação
- [[NEORV32]] - CPU de controle

---

## 🧠 Conceitos Fundamentais

### O que é uma Matriz Sistólica?

Uma **matriz sistólica** é uma rede de processadores (Processing Elements - PEs) que ritmicamente computam e passam dados através do sistema. O nome vem da analogia com o batimento cardíaco (sístole).

### Características

| Característica | Descrição |
|----------------|-----------|
| **Processamento** | Paralelo massivo |
| **Comunicação** | Local entre PEs adjacentes |
| **Fluxo de dados** | Ritmado por clock |
| **Eficiência** | Alta utilização de hardware |

### Vantagens para CNNs

- ✅ Paralelismo natural para convoluções
- ✅ Reutilização de dados (pesos e ativações)
- ✅ Alta eficiência energética
- ✅ Escalabilidade

---

## 📐 Arquitetura 8x8

### Visão Geral

```
┌─────────────────────────────────────────────────────────────┐
│              MATRIZ SISTÓLICA 8x8                            │
│                                                              │
│     Entrada de Pesos (W)                                     │
│           │                                                  │
│           ▼                                                  │
│     ┌─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┐      │
│     │ PE  │ PE  │ PE  │ PE  │ PE  │ PE  │ PE  │ PE  │      │
│     │0,0  │0,1  │0,2  │0,3  │0,4  │0,5  │0,6  │0,7  │      │
│     ├─────┼─────┼─────┼─────┼─────┼─────┼─────┼─────┤      │
│     │ PE  │ PE  │ PE  │ PE  │ PE  │ PE  │ PE  │ PE  │      │
│     │1,0  │1,1  │1,2  │1,3  │1,4  │1,5  │1,6  │1,7  │      │
│     ├─────┼─────┼─────┼─────┼─────┼─────┼─────┼─────┤      │
│     │ PE  │ PE  │ PE  │ PE  │ PE  │ PE  │ PE  │ PE  │      │
│     │2,0  │2,1  │2,2  │2,3  │2,4  │2,5  │2,6  │2,7  │      │
│     ├─────┼─────┼─────┼─────┼─────┼─────┼─────┼─────┤      │
│     │ PE  │ PE  │ PE  │ PE  │ PE  │ PE  │ PE  │ PE  │      │
│     │3,0  │3,1  │3,2  │3,3  │3,4  │3,5  │3,6  │3,7  │      │
│     ├─────┼─────┼─────┼─────┼─────┼─────┼─────┼─────┤      │
│     │ PE  │ PE  │ PE  │ PE  │ PE  │ PE  │ PE  │ PE  │      │
│     │4,0  │4,1  │4,2  │4,3  │4,4  │4,5  │4,6  │4,7  │      │
│     ├─────┼─────┼─────┼─────┼─────┼─────┼─────┼─────┤      │
│     │ PE  │ PE  │ PE  │ PE  │ PE  │ PE  │ PE  │ PE  │      │
│     │5,0  │5,1  │5,2  │5,3  │5,4  │5,5  │5,6  │5,7  │      │
│     ├─────┼─────┼─────┼─────┼─────┼─────┼─────┼─────┤      │
│     │ PE  │ PE  │ PE  │ PE  │ PE  │ PE  │ PE  │ PE  │      │
│     │6,0  │6,1  │6,2  │6,3  │6,4  │6,5  │6,6  │6,7  │      │
│     ├─────┼─────┼─────┼─────┼─────┼─────┼─────┼─────┤      │
│     │ PE  │ PE  │ PE  │ PE  │ PE  │ PE  │ PE  │ PE  │      │
│     │7,0  │7,1  │7,2  │7,3  │7,4  │7,5  │7,6  │7,7  │      │
│     └─────┴─────┴─────┴─────┴─────┴─────┴─────┴─────┘      │
│                         │                                    │
│                         ▼                                    │
│              Saída (Resultados)                              │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### Especificações

| Parâmetro | Valor |
|-----------|-------|
| **Dimensões** | 8x8 |
| **Total de PEs** | 64 |
| **Precisão** | INT8 (8-bit integer) |
| **DSP Blocks** | ~200 (mapeamento ideal nos 266 disponíveis) |
| **Operações por ciclo** | 64 MACs |

---

## 🔧 Processing Element (PE)

### Arquitetura de um PE

```
┌─────────────────────────────────────────────────────────────┐
│              PROCESSING ELEMENT (PE)                         │
│                                                              │
│  Entrada A ─────┐                                            │
│                 │                                            │
│                 ▼                                            │
│           ┌───────────┐                                      │
│           │           │                                      │
│           │   MAC     │◄──── Entrada W (Peso)               │
│           │  (Mult +  │                                      │
│           │   Acc)    │                                      │
│           │           │                                      │
│           └─────┬─────┘                                      │
│                 │                                            │
│                 ▼                                            │
│           ┌───────────┐                                      │
│           │ Registro  │                                      │
│           │ (Acc)     │                                      │
│           └─────┬─────┘                                      │
│                 │                                            │
│                 ├───────────────▶ Saída A (para PE adjacente)│
│                 │                                            │
│                 ▼                                            │
│           Saída P (Resultado parcial)                        │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### Operação do PE

Cada PE executa a operação:

```
acc = acc + (a × w)
```

Onde:
- `a` = entrada de ativação (do PE acima ou entrada externa)
- `w` = peso (carregado da memória)
- `acc` = acumulador (resultado parcial)

### Implementação em VHDL

```vhdl
entity processing_element is
    port (
        clk     : in  std_logic;
        reset   : in  std_logic;
        -- Entradas
        a_in    : in  signed(7 downto 0);   -- Ativação
        w_in    : in  signed(7 downto 0);   -- Peso
        p_in    : in  signed(15 downto 0);  -- Resultado parcial
        -- Saídas
        a_out   : out signed(7 downto 0);   -- Ativação para próximo PE
        p_out   : out signed(15 downto 0)   -- Resultado acumulado
    );
end entity;

architecture rtl of processing_element is
    signal acc : signed(15 downto 0);
begin
    process(clk, reset)
    begin
        if reset = '1' then
            acc <= (others => '0');
            a_out <= (others => '0');
            p_out <= (others => '0');
        elsif rising_edge(clk) then
            -- MAC operation
            acc <= p_in + (a_in * w_in);
            -- Pass-through
            a_out <= a_in;
            p_out <= acc;
        end if;
    end process;
end architecture;
```

---

## 📊 Fluxo de Dados

### Padrão de Fluxo

```
┌─────────────────────────────────────────────────────────────┐
│           FLUXO DE DADOS NA MATRIZ                           │
│                                                              │
│  Tempo t=0:                                                  │
│  ┌─────┬─────┬─────┬─────┐                                  │
│  │ A0  │     │     │     │  ← Primeira ativação entra      │
│  │ W0  │     │     │     │                                  │
│  └─────┴─────┴─────┴─────┘                                  │
│                                                              │
│  Tempo t=1:                                                  │
│  ┌─────┬─────┬─────┬─────┐                                  │
│  │ A1  │ A0  │     │     │  ← Dados fluem para direita     │
│  │ W1  │ W0  │     │     │                                  │
│  └─────┴─────┴─────┴─────┘                                  │
│                                                              │
│  Tempo t=2:                                                  │
│  ┌─────┬─────┬─────┬─────┐                                  │
│  │ A2  │ A1  │ A0  │     │                                  │
│  │ W2  │ W1  │ W0  │     │                                  │
│  └─────┴─────┴─────┴─────┘                                  │
│                                                              │
│  Tempo t=3:                                                  │
│  ┌─────┬─────┬─────┬─────┐                                  │
│  │ A3  │ A2  │ A1  │ A0  │  ← Matriz preenchida            │
│  │ W3  │ W2  │ W1  │ W0  │                                  │
│  └─────┴─────┴─────┴─────┘                                  │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### Tipos de Fluxo

| Fluxo | Direção | Dados |
|-------|---------|-------|
| **Ativações** | Horizontal (esquerda → direita) | Entradas da camada |
| **Pesos** | Vertical (cima → baixo) | Parâmetros da rede |
| **Parciais** | Vertical (cima → baixo) | Resultados acumulados |

---

## 🎯 Mapeamento para DSP Blocks

### DSP Blocks do Cyclone IV E

O Cyclone IV E possui **266 DSP blocks**, cada um capaz de realizar:
- Multiplicação 18×18 bits
- Multiplicação 9×9 bits (dois por bloco)
- Acumulação de 64 bits

### Estratégia de Mapeamento

```
┌─────────────────────────────────────────────────────────────┐
│           MAPEAMENTO PARA DSP BLOCKS                         │
│                                                              │
│  Cada PE (INT8 × INT8) pode ser mapeado como:               │
│                                                              │
│  ┌─────────────────────────────────────────────────────┐   │
│  │  DSP Block (18×18)                                   │   │
│  │                                                      │   │
│  │  ┌─────────────┐    ┌─────────────┐                 │   │
│  │  │  8×8 Mult   │ ou │  9×9 Mult   │ + │ 9×9 Mult  │  │   │
│  │  │  (1 PE)     │    │  (2 PEs)    │   │ (2 PEs)   │  │   │
│  │  └─────────────┘    └─────────────┘                 │   │
│  │                                                      │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                              │
│  Estratégia recomendada: 1 PE por DSP (redundância)         │
│  ou 2 PEs por DSP (máxima eficiência)                       │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### Utilização de Recursos

| Configuração | DSP Blocks | Eficiência |
|--------------|------------|------------|
| **1 PE/DSP** | 64 | 100% (redundância) |
| **2 PEs/DSP** | 32 | 50% (máxima eficiência) |
| **Recomendada** | ~64-128 | 75% |

---

## 📈 Performance

### Throughput Teórico

| Frequência | Throughput |
|------------|------------|
| **50 MHz** | 3.2 GOPS |
| **100 MHz** | 6.4 GOPS |
| **120 MHz** | 7.68 GOPS |

### Cálculo

```
Throughput = N_PEs × Frequência
           = 64 × 100 MHz
           = 6.4 × 10^9 operações/segundo
           = 6.4 GOPS
```

### Eficiência

| Métrica | Valor |
|---------|-------|
| **Utilização DSP** | ~75% |
| **Utilização LUT** | ~45% |
| **Eficiência energética** | Alta (INT8) |

---

## 🔄 Operações Suportadas

### 1. Convolução 2D

```
┌─────────────────────────────────────────────────────────────┐
│           CONVOLUÇÃO 2D NA MATRIZ SISTÓLICA                  │
│                                                              │
│  Kernel 3×3:                                                 │
│  ┌─────┬─────┬─────┐                                        │
│  │ w00 │ w01 │ w02 │                                        │
│  ├─────┼─────┼─────┤                                        │
│  │ w10 │ w11 │ w12 │                                        │
│  ├─────┼─────┼─────┤                                        │
│  │ w20 │ w21 │ w22 │                                        │
│  └─────┴─────┴─────┘                                        │
│                                                              │
│  Mapeamento:                                                 │
│  • Pesos carregados verticalmente                            │
│  • Ativações fluem horizontalmente                           │
│  • Resultado = Σ(w × a) para cada posição                   │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### 2. Multiplicação de Matrizes

```
C = A × B

Onde:
- A: Matriz M×K (ativações)
- B: Matriz K×N (pesos)
- C: Matriz M×N (resultado)
```

### 3. Camada Fully Connected

- Caso especial de multiplicação de matrizes
- A: vetor 1×K (entrada)
- B: matriz K×N (pesos)
- C: vetor 1×N (saída)

---

## ⚙️ Interface com NEORV32

### Sinais de Controle

| Sinal | Direção | Descrição |
|-------|---------|-----------|
| `clk` | Input | Clock do sistema |
| `reset` | Input | Reset síncrono |
| `start` | Input | Inicia processamento |
| `done` | Output | Processamento concluído |
| `busy` | Output | Matriz ocupada |

### Interface de Dados

| Sinal | Largura | Descrição |
|-------|---------|-----------|
| `weights_addr` | 16-bit | Endereço dos pesos |
| `weights_data` | 8-bit | Dados dos pesos |
| `input_addr` | 16-bit | Endereço da entrada |
| `input_data` | 8-bit | Dados de entrada |
| `output_data` | 16-bit | Dados de saída |

### Registradores de Controle

```
┌─────────────────────────────────────────────────────────────┐
│           REGISTRADORES DE CONTROLE                          │
│                                                              │
│  Endereço    │ Registrador      │ Função                    │
│  ────────────┼──────────────────┼───────────────────────── │
│  0x00        │ CTRL             │ Controle (start, reset)   │
│  0x04        │ STATUS           │ Status (done, busy)       │
│  0x08        │ WEIGHTS_BASE     │ Base dos pesos            │
│  0x0C        │ INPUT_BASE       │ Base da entrada           │
│  0x10        │ OUTPUT_BASE      │ Base da saída             │
│  0x14        │ CONFIG           │ Configuração (dimensões)  │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

---

## 📚 Referências

- [Systolic Array as an CNN Accelerator](https://hackmd.io/@fpga/SyV8U2GD3)
- [Design and Implementation of a Highly Parallel Systolic Array on FPGA](https://www.ijerm.com/download_data/IJERM1103010.pdf)
- [Google TPU Paper](https://arxiv.org/abs/1704.04760)

---

## 🏷️ Tags

#SystolicArray #PE #MAC #DSP #CNN #INT8 #ParallelProcessing #HardwareAcceleration

---

**Veja também:**
- [[Implementation Matrix]] - Visão geral da implementação
- [[NEORV32]] - CPU de controle
- [[Bus Integration]] - Integração com o sistema
- [[HLS Design Flow]] - Como gerar a matriz sistólica
