# Referências - Bibliografia do TCC

> **Lista Completa de Referências e Recursos**

---

## 📋 Visão Geral

Esta página contém todas as referências bibliográficas e recursos utilizados no desenvolvimento do TCC sobre aceleração de redes neurais em FPGA Cyclone IV E.

### 🔗 Links Relacionados
- [[Home]] - Página principal

---

## 📚 Referências do Documento Original

### NEORV32 e RISC-V

1. **NEORV32 README - OpenCores**
   - Acessado: Fevereiro 24, 2026
   - URL: https://opencores.org/websvn/filedetails?repname=neorv32&path=%2Fneorv32%2Ftrunk%2FREADME.md&rev=4
   - Tópico: [[NEORV32]]

2. **The NEORV32 RISC-V Processor - Data Sheet**
   - Acessado: Fevereiro 24, 2026
   - URL: https://stnolting.github.io/neorv32/
   - Tópico: [[NEORV32]]

3. **Optimizing Cryptographic Performance and Education: AES Encryption and FPGA Hardware Acceleration**
   - Fonte: Electrical & Systems Engineering, Washington University
   - Acessado: Fevereiro 24, 2026
   - URL: https://ese.washu.edu/documents/Optimizing-Cryptographic-Performance-and-Education-AES-Encryption-and-FPGA-Hardware-Acceleration.pdf
   - Tópico: [[NEORV32]], [[FPGA AI Suite Analysis]]

4. **NEORV32 — Zephyr Project Documentation**
   - Acessado: Fevereiro 24, 2026
   - URL: https://docs.zephyrproject.org/latest/boards/others/neorv32/doc/index.html
   - Tópico: [[NEORV32]]

5. **Bare-Metal RISC-V + NVDLA SoC for Efficient Deep Learning Inference**
   - Fonte: arXiv.org
   - Acessado: Fevereiro 24, 2026
   - URL: https://arxiv.org/html/2508.16095v2
   - Tópico: [[NEORV32]], [[Systolic Array]]

### FPGA e Hardware

6. **FPGA Boards - Cyclone IV - The Video and Embedded Evaluation Kit - Multi-touch, Second Edition (VEEK-MT2)**
   - Fonte: Terasic
   - Acessado: Fevereiro 24, 2026
   - URL: https://www.terasic.com.tw/cgi-bin/page/archive.pl?Language=English&CategoryNo=139&No=1020&PartNo=2
   - Tópico: [[DE2-115 Board]], [[Clock Management]]

7. **ALTERA CYCLONE IV FPGA DEVELOPMENT BOARD - MODEL: DE-115**
   - Fonte: ablelogic
   - Acessado: Fevereiro 24, 2026
   - URL: https://www.vvtec.com/de115.html
   - Tópico: [[DE2-115 Board]]

### Matriz Sistólica e Aceleradores

8. **Systolic Array as an CNN Accelerator - Final Project**
   - Fonte: HackMD - FPGA Group6
   - Acessado: Fevereiro 24, 2026
   - URL: https://hackmd.io/@fpga/SyV8U2GD3
   - Tópico: [[Systolic Array]]

9. **Design and Implementation of a Highly Parallel Systolic Array on FPGA**
   - Fonte: IJERM (International Journal of Engineering Research and Management)
   - Acessado: Fevereiro 24, 2026
   - URL: https://www.ijerm.com/download_data/IJERM1103010.pdf
   - Tópico: [[Systolic Array]]

### Barramentos e Integração

10. **The NEORV32 RISC-V Processor - User Guide**
    - Acessado: Fevereiro 24, 2026
    - URL: https://stnolting.github.io/neorv32/ug/
    - Tópico: [[NEORV32]], [[Bus Integration]]

---

## 📖 Referências Adicionais Recomendadas

### Intel/Altera Documentation

| Documento | URL | Tópico |
|-----------|-----|--------|
| **Cyclone IV Device Handbook** | https://www.intel.com/content/www/us/en/docs/programmable/149814/current/overview.html | [[DE2-115 Board]] |
| **Intel HLS Compiler User Guide** | https://www.intel.com/content/www/us/en/docs/programmable/683623/current/overview.html | [[HLS Design Flow]] |
| **Intel FPGA AI Suite** | https://www.intel.com/content/www/us/en/docs/programmable/683948/current/overview.html | [[FPGA AI Suite Analysis]] |
| **TimeQuest Timing Analyzer** | https://www.intel.com/content/www/us/en/docs/programmable/683426/current/overview.html | [[Clock Management]] |
| **Avalon Interface Specifications** | https://www.intel.com/content/www/us/en/docs/programmable/683091/current/avalon-interface-specifications.html | [[Bus Integration]] |

### Terasic Documentation

| Documento | URL | Tópico |
|-----------|-----|--------|
| **DE2-115 User Manual** | https://www.terasic.com.tw/cgi-bin/page/archive.pl?Language=English&CategoryNo=139&No=502 | [[DE2-115 Board]] |
| **DE2-115 Schematic** | https://www.terasic.com.tw/cgi-bin/page/archive.pl?Language=English&CategoryNo=139&No=502&PartNo=4 | [[DE2-115 Board]] |
| **DE2-115 Tutorials** | https://www.terasic.com.tw/cgi-bin/page/archive.pl?Language=English&CategoryNo=139&No=502&PartNo=7 | [[DE2-115 Board]] |

### hls4ml e Machine Learning

| Documento | URL | Tópico |
|-----------|-----|--------|
| **hls4ml Documentation** | https://fastmachinelearning.org/hls4ml/ | [[HLS Design Flow]] |
| **hls4ml GitHub** | https://github.com/fastmachinelearning/hls4ml | [[HLS Design Flow]] |
| **TensorFlow Model Optimization** | https://www.tensorflow.org/model_optimization | [[HLS Design Flow]] |
| **PyTorch Quantization** | https://pytorch.org/docs/stable/quantization.html | [[HLS Design Flow]] |

### RISC-V e NEORV32

| Documento | URL | Tópico |
|-----------|-----|--------|
| **NEORV32 GitHub** | https://github.com/stnolting/neorv32 | [[NEORV32]] |
| **RISC-V Specifications** | https://riscv.org/technical/specifications/ | [[NEORV32]] |
| **Wishbone Specification** | https://opencores.org/howto/wishbone | [[Bus Integration]] |

### Artigos Acadêmicos

| Artigo | Tópico |
|--------|--------|
| **Google TPU Paper** - "In-Datacenter Performance Analysis of a Tensor Processing Unit" | [[Systolic Array]] |
| **Eyeriss** - "Eyeriss: A Spatial Architecture for Energy-Efficient Dataflow for Convolutional Neural Networks" | [[Systolic Array]] |
| **hls4ml Paper** - "Fast inference of deep neural networks in high-energy physics for real-time applications" | [[HLS Design Flow]] |

---

## 🎓 Categorias de Referências

### Por Tópico

```
┌─────────────────────────────────────────────────────────────┐
│           REFERÊNCIAS POR TÓPICO                             │
│                                                              │
│  [[NEORV32]]                                                 │
│  ├── [1] NEORV32 README - OpenCores                         │
│  ├── [2] NEORV32 Data Sheet                                 │
│  ├── [3] AES Encryption and FPGA                            │
│  ├── [4] Zephyr Project Documentation                       │
│  ├── [5] Bare-Metal RISC-V + NVDLA                          │
│  └── [10] NEORV32 User Guide                                │
│                                                              │
│  [[DE2-115 Board]]                                           │
│  ├── [6] VEEK-MT2 - Terasic                                 │
│  ├── [7] DE-115 - ablelogic                                 │
│  ├── Cyclone IV Device Handbook                             │
│  └── DE2-115 User Manual                                    │
│                                                              │
│  [[Systolic Array]]                                          │
│  ├── [8] Systolic Array as CNN Accelerator                  │
│  ├── [9] Highly Parallel Systolic Array                     │
│  ├── [5] Bare-Metal RISC-V + NVDLA                          │
│  └── Google TPU Paper                                        │
│                                                              │
│  [[Bus Integration]]                                         │
│  ├── [10] NEORV32 User Guide                                │
│  ├── Avalon Interface Specifications                        │
│  └── Wishbone Specification                                 │
│                                                              │
│  [[HLS Design Flow]]                                         │
│  ├── hls4ml Documentation                                   │
│  ├── Intel HLS Compiler User Guide                          │
│  └── TensorFlow Model Optimization                          │
│                                                              │
│  [[Clock Management]]                                        │
│  ├── [6] VEEK-MT2 - Terasic                                 │
│  ├── Cyclone IV Device Handbook                             │
│  └── TimeQuest Timing Analyzer                              │
│                                                              │
│  [[FPGA AI Suite Analysis]]                                  │
│  ├── [3] AES Encryption and FPGA                            │
│  └── Intel FPGA AI Suite                                    │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

---

## 🔗 Links Úteis

### Comunidades

| Comunidade | URL |
|------------|-----|
| **FPGA Reddit** | https://www.reddit.com/r/FPGA/ |
| **RISC-V International** | https://riscv.org/ |
| **Intel FPGA Forum** | https://community.intel.com/t5/Intel-Quartus-Primes/ct-p/intel-quartus-primes |
| **OpenCores** | https://opencores.org/ |

### Ferramentas

| Ferramenta | URL |
|------------|-----|
| **Quartus Prime** | https://www.intel.com/content/www/us/en/software/programmable/quartus-prime/overview.html |
| **ModelSim** | https://www.intel.com/content/www/us/en/software/programmable/modelsim/overview.html |
| **Python** | https://www.python.org/ |
| **TensorFlow** | https://www.tensorflow.org/ |
| **PyTorch** | https://pytorch.org/ |

---

## 📝 Como Citar

### Formato ABNT

```
TERASIC. DE2-115 User Manual. Disponível em: 
<https://www.terasic.com.tw/cgi-bin/page/archive.pl?Language=English&CategoryNo=139&No=502>. 
Acesso em: fev. 2026.

STNOLTING. The NEORV32 RISC-V Processor. Disponível em: 
<https://stnolting.github.io/neorv32/>. 
Acesso em: fev. 2026.

INTEL. Cyclone IV Device Handbook. Disponível em: 
<https://www.intel.com/content/www/us/en/docs/programmable/149814/current/overview.html>. 
Acesso em: fev. 2026.
```

### Formato IEEE

```
[1] Terasic, "DE2-115 User Manual," 2026. [Online]. Available: 
https://www.terasic.com.tw/cgi-bin/page/archive.pl?Language=English&CategoryNo=139&No=502

[2] S. Nolting, "The NEORV32 RISC-V Processor," 2026. [Online]. Available: 
https://stnolting.github.io/neorv32/

[3] Intel, "Cyclone IV Device Handbook," 2026. [Online]. Available: 
https://www.intel.com/content/www/us/en/docs/programmable/149814/current/overview.html
```

---

## 🏷️ Tags

#References #Bibliography #Documentation #Resources #Links

---

**Veja também:**
- [[Home]] - Página principal
- [[Glossário]] - Termos técnicos (se disponível)
