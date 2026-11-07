# 🏠 Aceleração de Redes Neurais em FPGA Cyclone IV E

> **TCC Principal:** Implementação de aceleração de Inteligência Artificial no FPGA Cyclone IV E (DE2-115)

---

## 📋 Visão Geral do Projeto

Este projeto de TCC foca na aceleração de redes neurais utilizando o FPGA **Cyclone IV E** (modelo EP4CE115) na placa de desenvolvimento **DE2-115**. O objetivo principal é criar um equilíbrio fino entre o controle de fluxo por software e o processamento paralelo massivo por hardware.

### 🎯 Objetivos

- Implementar um acelerador de IA usando processamento paralelo em hardware
- Utilizar o soft-core [[NEORV32]] como controlador do sistema
- Alcançar ganhos de velocidade de até **350%** em relação à execução puramente em software
- Demonstrar throughput de até **59.52 GOPS** a 120MHz

---

## 🗺️ Mapa do Conhecimento

### Arquitetura e Hardware
- [[NEORV32]] - Soft-core RISC-V como CPU de controle
- [[DE2-115 Board]] - Especificações da placa de desenvolvimento
- [[Systolic Array]] - Acelerador de IA com matriz sistólica 8x8

### Barramento e Integração
- [[Bus Integration]] - Desenvolvimento do barramento (CFS, Wishbone, Avalon-MM)
- [[Memory Management]] - Gestão de memória SDRAM e buffers

### Ferramentas e Fluxo de Design
- [[FPGA AI Suite Analysis]] - Análise e limitações da Altera FPGA AI Suite
- [[HLS Design Flow]] - Fluxo de design usando HLS e hls4ml
- [[Clock Management]] - Gestão de clock e PLLs

### Implementação
- [[Implementation Matrix]] - Matriz de implementação recomendada
- [[Performance Metrics]] - Métricas de desempenho e benchmarks

---

## 📊 Arquitetura do Sistema

```
┌─────────────────────────────────────────────────────────────┐
│                    FPGA Cyclone IV E                         │
│  ┌─────────────────────────────────────────────────────┐    │
│  │                    NEORV32                           │    │
│  │              (CPU de Controle)                       │    │
│  │           ~2,300 LUTs (<5% do chip)                  │    │
│  └────────────────────┬────────────────────────────────┘    │
│                       │ Wishbone/Avalon                      │
│  ┌────────────────────┴────────────────────────┐           │
│  │              Acelerador IA                  │           │
│  │         Matriz Sistólica 8x8 (INT8)         │           │
│  │         >95% ut recursos do chip            │           │
│  └─────────────────────────────────────────────┘           │
│                       │                                    │
│  ┌────────────────────┴────────────────────────┐           │
	│  │         Controlador   (128MB)           │           │
│  └─────────────────────────────────────────────┘           │
└────────────────────────────────────────────────────────────┘
```

---

## 🔧 Componentes Principais

| Componente | Tecnologia | Justificativa |
|------------|------------|---------------|
| CPU de Controle | NEORV32 (RV32IM) | Baixo consumo de área e excelente documentação |
| Acelerador IA | Matriz Sistólica 8x8 (INT8) | Mapeamento ideal nos 266 blocos DSP |
| Barramento | Wishbone com wrapper Avalon | Compatibilidade com ecossistema Terasic/Intel |
| Fluxo de Design | Python → hls4ml/C++ HLS | Substitui ausência do AI Suite |
| Clock Final | 100MHz (via PLL) | Equilíbrio entre performance e timing closure |

---

## 📚 Documentação

- [[Referências]] - Lista completa de referências bibliográficas
- [[Glossário]] - Termos técnicos e definições
- [[Notas de Estudo]] - Anotações e insights

---

## 🏷️ Tags

#FPGA #CycloneIV #NEORV32 #RISC-V #NeuralNetworks #AI #HardwareAcceleration #SystolicArray #HLS #DE2-115

---

## Status do Projeto

- [x] Analise de viabilidade
- [x] Definicao da arquitetura
- [x] Implementacao do NEORV32 (2026-03-26)
- [x] Implementacao do PE (Processing Element) INT8 MAC
- [x] Implementacao da matriz sistolica 8x8 weight-stationary
- [x] Interface Wishbone (neorv32_systolic_wb_accelerator)
- [x] Testbench standalone (simulacao GHDL)
- [x] Testbench integrado NEORV32 + XBUS + acelerador
- [x] Teste standalone na FPGA DE2-115 (resultado 0x24 confirmado nos LEDs)
- [ ] Integracao completa NEORV32 + acelerador via XBUS
- [ ] Firmware C para inferencia de redes neurais
- [ ] Acesso direto a SDRAM via DMA
- [ ] Documentacao final (TCC)

---

*Ultima atualizacao: 2026-05-18*
