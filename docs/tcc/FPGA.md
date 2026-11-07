# FPGA - Field-Programmable Gate Array

> **Visão Geral sobre FPGAs e o Projeto de Aceleração de IA**

---

## 📋 O que é um FPGA?

Um **FPGA (Field-Programmable Gate Array)** é um circuito integrado que pode ser programado após a fabricação. Diferente de ASICs (Application-Specific Integrated Circuits), os FPGAs oferecem flexibilidade para reconfigurar a lógica interna.

### Características Principais

| Característica | Descrição |
|----------------|-----------|
| **Reconfigurabilidade** | Pode ser reprogramado múltiplas vezes |
| **Paralelismo** | Execução verdadeiramente paralela |
| **Baixa Latência** | Processamento em tempo real |
| **Prototipagem** | Ideal para validação de designs |

---

## 🎯 FPGA no Contexto do TCC

Este projeto utiliza o FPGA **Cyclone IV E** (modelo EP4CE115) na placa de desenvolvimento **DE2-115** para acelerar redes neurais artificiais.

### Diagrama do Projeto

![[Pasted image 20260315174423.png]]

---

## 🗺️ Mapa de Conteúdo

### Arquitetura e Hardware
- [[DE2-115 Board]] - Especificações completas da placa
- [[NEORV32]] - Soft-core RISC-V como CPU de controle
- [[Systolic Array]] - Acelerador de IA com matriz sistólica 8x8

### Integração e Comunicação
- [[Bus Integration]] - Barramentos (CFS, Wishbone, Avalon-MM)

### Ferramentas e Design
- [[FPGA AI Suite Analysis]] - Limitações da AI Suite para Cyclone IV
- [[HLS Design Flow]] - Fluxo de design com High-Level Synthesis
- [[Clock Management]] - Gestão de clock e PLLs

### Implementação
- [[Implementation Matrix]] - Matriz de componentes recomendados
- [[Home]] - Página principal do projeto

### Recursos
- [[Referências]] - Bibliografia completa

---

## 📊 Comparação: FPGA vs Outras Tecnologias

| Critério | FPGA | CPU | GPU | ASIC |
|----------|------|-----|-----|------|
| **Flexibilidade** | Alta | Alta | Média | Baixa |
| **Paralelismo** | Alto | Baixo | Alto | Alto |
| **Latência** | Baixa | Alta | Média | Baixa |
| **Eficiência Energética** | Média | Baixa | Baixa | Alta |
| **Custo de Desenvolvimento** | Médio | Baixo | Baixo | Alto |
| **Tempo de Desenvolvimento** | Médio | Curto | Curto | Longo |

---

## 🔧 Componentes Internos de um FPGA

```
┌─────────────────────────────────────────────────────────────┐
│           ARQUITETURA INTERNA DO FPGA                        │
│                                                              │
│  ┌─────────────────────────────────────────────────────┐   │
│  │           Lógica Configurável (CLB)                  │   │
│  │  ┌─────────┐  ┌─────────┐  ┌─────────┐             │   │
│  │  │   LUT   │  │   LUT   │  │   LUT   │  ...        │   │
│  │  │  + FF   │  │  + FF   │  │  + FF   │             │   │
│  │  └─────────┘  └─────────┘  └─────────┘             │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                              │
│  ┌─────────────────────────────────────────────────────┐   │
│  │           Blocos de Memória (BRAM/M9K)               │   │
│  │  ┌─────────┐  ┌─────────┐  ┌─────────┐             │   │
│  │  │  M9K    │  │  M9K    │  │  M9K    │  ...        │   │
│  │  │ Block   │  │ Block   │  │ Block   │             │   │
│  │  └─────────┘  └─────────┘  └─────────┘             │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                              │
│  ┌─────────────────────────────────────────────────────┐   │
│  │           Blocos DSP (Multiplicadores)               │   │
│  │  ┌─────────┐  ┌─────────┐  ┌─────────┐             │   │
│  │  │  DSP    │  │  DSP    │  │  DSP    │  ...        │   │
│  │  │ 18×18   │  │ 18×18   │  │ 18×18   │             │   │
│  │  └─────────┘  └─────────┘  └─────────┘             │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                              │
│  ┌─────────────────────────────────────────────────────┐   │
│  │           PLLs (Phase-Locked Loops)                  │   │
│  │  ┌─────────┐  ┌─────────┐  ┌─────────┐  ┌────────┐ │   │
│  │  │  PLL 1  │  │  PLL 2  │  │  PLL 3  │  │ PLL 4  │ │   │
│  │  └─────────┘  └─────────┘  └─────────┘  └────────┘ │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                              │
│  ┌─────────────────────────────────────────────────────┐   │
│  │           I/O Blocks                                 │   │
│  │  ┌──────────────────────────────────────────────┐  │   │
│  │  │  GPIO, LVDS, DDR, PCIe, etc.                 │  │   │
│  │  └──────────────────────────────────────────────┘  │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

---

## 🚀 Vantagens para Aceleração de IA

### 1. Paralelismo Massivo
- Execução simultânea de múltiplas operações
- Ideal para operações de multiplicação-acumulação (MAC)

### 2. Baixa Latência
- Processamento em tempo real
- Ideal para aplicações críticas

### 3. Eficiência Energética
- Melhor que GPUs para workloads específicos
- Consumo proporcional à utilização

### 4. Flexibilidade
- Atualização de algoritmos sem novo hardware
- Suporte a diferentes tipos de redes neurais

---

## 📚 Aprenda Mais

### Documentação Oficial
- [[Referências]] - Links para documentação oficial

### Tutoriais Recomendados
1. Comece pela [[Home]] para visão geral do projeto
2. Estude a [[DE2-115 Board]] para conhecer o hardware
3. Leia sobre [[NEORV32]] para entender o controlador
4. Explore a [[Systolic Array]] para o acelerador

---

## 🏷️ Tags

#FPGA #CycloneIV #Hardware #Reconfigurable #ParallelProcessing

---

**Veja também:**
- [[Home]] - Página principal do projeto
- [[DE2-115 Board]] - Especificações da placa
- [[Implementation Matrix]] - Visão geral da implementação
