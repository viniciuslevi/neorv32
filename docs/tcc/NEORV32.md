# NEORV32 - Soft-Core RISC-V

> **Processador de Controle para Aceleração de IA no Cyclone IV E**

---

## 📋 Visão Geral

O **NEORV32** é um soft-core RISC-V escolhido estrategicamente para a placa [[DE2-115 Board|DE2-115]]. É escrito em **VHDL puro**, sem dependências de primitivas de fabricantes específicos, facilitando a portabilidade e a depuração no Quartus.

### 🔗 Links Relacionados
- [[Home]] - Página principal
- [[Bus Integration]] - Integração com barramentos
- [[Implementation Matrix]] - Matriz de implementação

---

## ⚙️ Especificações Técnicas

### Configuração Recomendada: RV32IMC

| Extensão | Descrição | Benefício |
|----------|-----------|-----------|
| **I** (Integer) | Instruções inteiras base | Operações aritméticas fundamentais |
| **M** (Multiplication) | Multiplicação e divisão por hardware | Essencial para pré-processamento de IA |
| **C** (Compressed) | Instruções comprimidas | Redução de footprint de código |

### Consumo de Recursos no Cyclone IV

```
┌────────────────────────────────────────┐
│  NEORV32 (RV32IMC)                     │
│  ≈ 2,300 LUTs                          │
│  < 5% do chip EP4CE115                 │
│  > 95% livre para o acelerador de IA   │
└────────────────────────────────────────┘
```

---

## 🎯 Papel do Processador no Sistema

O NEORV32 **não executa as convoluções** diretamente. Suas responsabilidades são:

### 1. Gerenciamento de Memória
- Carrega pesos da memória SDRAM externa para as memórias internas (M9K)
- Gerencia transferências de dados

### 2. Controle do Acelerador
- Inicia o processamento do acelerador de IA
- Configura parâmetros de operação

### 3. Coleta de Resultados
- Recebe os resultados finais do acelerador
- Prepara dados para exibição (VGA ou LCD)

### 4. Pré-processamento
- Normalização de pixels
- Conversão de formatos de dados
- Cálculos de suporte (usando extensão M)

---

## 📐 Arquitetura Interna

```
┌─────────────────────────────────────────────────────────────┐
│                      NEORV32                                 │
│  ┌─────────────────────────────────────────────────────┐   │
│  │                   CPU Core                           │   │
│  │            (RV32IMC Pipeline)                        │   │
│  └─────────────────────────────────────────────────────┘   │
│                          │                                   │
│  ┌───────────────────────┼───────────────────────┐         │
│  │                       │                       │         │
│  ▼                       ▼                       ▼         │
│ ┌─────────┐    ┌─────────────────┐    ┌─────────────┐     │
│ │  IMEM   │    │   Wishbone      │    │   DMEM      │     │
│ │ (Instr) │    │   Interface     │    │  (Data)     │     │
│ └─────────┘    └────────┬────────┘    └─────────────┘     │
│                          │                                   │
│                          ▼                                   │
│              ┌─────────────────────┐                        │
│              │   CFS / Peripherals │                        │
│              │   (Acelerador IA)   │                        │
│              └─────────────────────┘                        │
└─────────────────────────────────────────────────────────────┘
```

---

## 🔧 Extensão M (Multiplicação/Divisão)

A ativação da extensão **'M'** é **essencial** para o controle da IA.

### Benefícios

| Operação | Sem Extensão M | Com Extensão M |
|----------|----------------|----------------|
| Multiplicação | Emulação por software (~30 ciclos) | Hardware (~3-5 ciclos) |
| Divisão | Emulação por software (~40 ciclos) | Hardware (~8-34 ciclos) |
| Normalização de pixels | Lento | Otimizado |

### Aplicações no Pré-processamento

```c
// Normalização de pixel (0-255 → 0-1)
float normalize(uint8_t pixel) {
    return (float)pixel / 255.0f;  // Divisão acelerada por hardware
}

// Escalonamento de features
int32_t scale_feature(int32_t value, int32_t factor) {
    return value * factor;  // Multiplicação em hardware
}
```

---

## 🔄 Interface de Barramento

### Wishbone (Nativo)

O NEORV32 utiliza nativamente o padrão **Wishbone** para comunicação com periféricos.

### Conversão para Avalon-MM

Para integração com IPs da Intel via Platform Designer (Qsys):

```
┌─────────────┐      ┌──────────────┐      ┌─────────────┐
│  NEORV32    │      │   Wishbone   │      │   Avalon    │
│  Wishbone   │ ───▶ │   Wrapper    │ ───▶ │   Bus       │
│  Interface  │      │              │      │  (Qsys)     │
└─────────────┘      └──────────────┘      └─────────────┘
```

---

## 📚 Documentação e Recursos

### Oficiais
- [NEORV32 GitHub Pages - Data Sheet](https://stnolting.github.io/neorv32/)
- [NEORV32 User Guide](https://stnolting.github.io/neorv32/ug/)
- [OpenCores Repository](https://opencores.org/websvn/filedetails?repname=neorv32&path=%2Fneorv32%2Ftrunk%2FREADME.md&rev=4)

### Integração
- [Zephyr Project Documentation](https://docs.zephyrproject.org/latest/boards/others/neorv32/doc/index.html)

### Acadêmicos
- [AES Encryption and FPGA Hardware Acceleration](https://ese.washu.edu/documents/Optimizing-Cryptographic-Performance-and-Education-AES-Encryption-and-FPGA-Hardware-Acceleration.pdf)
- [Bare-Metal RISC-V + NVDLA SoC](https://arxiv.org/html/2508.16095v2)

---

## ⚡ Vantagens para o TCC

1. **Baixo consumo de área**: ~2,300 LUTs permite espaço abundante para o acelerador
2. **Documentação excelente**: Facilita o aprendizado e implementação
3. **VHDL puro**: Sem dependências de fabricante, fácil depuração
4. **Extensão M**: Acelera cálculos de pré-processamento
5. **Wishbone nativo**: Compatível com wrappers para Avalon-MM

---

## 🏷️ Tags

#NEORV32 #RISC-V #SoftCore #VHDL #CPU #ControlUnit #Wishbone #CycloneIV

---

**Veja também:**
- [[Bus Integration]] - Integração via CFS e Wishbone
- [[Systolic Array]] - Acelerador de IA
- [[Implementation Matrix]] - Visão geral da implementação
