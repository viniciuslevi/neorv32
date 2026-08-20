# Performance Comparison - FPGA vs CPU (i7)

> **Análise Comparativa: Acelerador FPGA Cyclone IV vs Intel Core i7**

---

## 📋 Visão Geral

Esta nota analisa se o acelerador de CNN baseado em FPGA Cyclone IV E pode superar um processador Intel Core i7 em desempenho para inferência de redes neurais convolucionais.

### 🔗 Links Relacionados
- [[Systolic Array]] - Arquitetura do acelerador
- [[Clock Management]] - Métricas de throughput
- [[Implementation Matrix]] - Especificações do sistema

---

## ⚠️ Resposta Direta: DEPENDE DO CENÁRIO

### Resumo Rápido

| Cenário | FPGA Cyclone IV | Intel i7 | Vencedor |
|---------|-----------------|----------|----------|
| **CNN pequena (MNIST)** | Pode vencer | Bom | 🏆 FPGA (possível) |
| **CNN média (CIFAR-10)** | Similar | Melhor | 🤝 Empate/i7 |
| **CNN grande (ImageNet)** | Lento | Muito melhor | 🏆 i7 |
| **Batch size = 1** | Vantagem | Desvantagem | 🏆 FPGA |
| **Batch size grande** | Limitado | Excelente | 🏆 i7 |
| **Latência** | Muito baixa | Alta | 🏆 FPGA |
| **Throughput bruto** | Limitado | Alto | 🏆 i7 |

---

## 📊 Análise Detalhada

### 1. Especificações Comparativas

#### FPGA Cyclone IV E (DE2-115)

| Parâmetro | Valor |
|-----------|-------|
| **Clock** | 100-120 MHz |
| **Matriz Sistólica** | 8×8 = 64 PEs |
| **Precisão** | INT8 |
| **Throughput Teórico** | 6.4-7.68 GOPS |
| **Memória** | 128 MB SDRAM (lenta) |
| **Largura de banda** | ~3.2 GB/s |

#### Intel Core i7 (Genérico 8ª-12ª geração)

| Parâmetro | Valor |
|-----------|-------|
| **Clock** | 3.0-5.0 GHz |
| **Cores/Threads** | 6-8 / 12-16 |
| **Precisão** | FP32/INT8 (AVX-512 VNNI) |
| **Throughput Teórico** | 500-2000 GOPS (INT8) |
| **Memória** | 16-64 GB DDR4/DDR5 |
| **Largura de banda** | 50-100 GB/s |

### 2. Gap de Performance

```
┌─────────────────────────────────────────────────────────────┐
│           COMPARAÇÃO DE THROUGHPUT                           │
│                                                              │
│  FPGA Cyclone IV (100 MHz)                                   │
│  ████████░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░ 6.4 GOPS     │
│                                                              │
│  FPGA Cyclone IV (120 MHz)                                   │
│  ██████████░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░ 7.68 GOPS    │
│                                                              │
│  i7-8700K (AVX2, 6 cores)                                   │
│  ████████████████████████████████████████████ ~300 GOPS    │
│                                                              │
│  i7-12700K (AVX-512 VNNI, 12 cores)                         │
│  ████████████████████████████████████████████████████ ~800 GOPS│
│                                                              │
│  Gap: FPGA é ~50-100x mais lento em throughput bruto        │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

---

## 🎯 Quando o FPGA PODE Vencer

### Cenário 1: Latência de Inferência (Batch=1)

```
┌─────────────────────────────────────────────────────────────┐
│           LATÊNCIA: BATCH SIZE = 1                           │
│                                                              │
│  FPGA:                                                       │
│  • Pipeline dedicado                                         │
│  • Sem overhead de SO                                       │
│  • Latência: ~10-100 μs                                     │
│                                                              │
│  i7:                                                         │
│  • Overhead de framework (TensorFlow, PyTorch)              │
│  • Cache misses                                             │
│  • Latência: ~1-10 ms                                       │
│                                                              │
│  🏆 FPGA pode ser 10-100x mais rápido em LATÊNCIA          │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### Cenário 2: CNN Muito Pequena

| CNN | Parâmetros | Operações | FPGA (estimado) | i7 (Python) |
|-----|------------|-----------|-----------------|-------------|
| **LeNet-5** | ~60K | ~0.5M | ~0.8ms | ~2-5ms |
| **Mini-CNN** | ~10K | ~0.1M | ~0.2ms | ~1-3ms |

Para redes **muito pequenas**, o overhead do framework no i7 pode tornar o FPGA mais rápido.

### Cenário 3: Sistema Embarcado/Edge

```
┌─────────────────────────────────────────────────────────────┐
│           COMPARAÇÃO EM AMBIENTE EMBEDDED                    │
│                                                              │
│  FPGA Cyclone IV:                                            │
│  • Consumo: 5-10W                                            │
│  • Eficiência: ~0.8 GOPS/W                                   │
│                                                              │
│  i7 Desktop:                                                  │
│  • Consumo: 65-125W                                          │
│  • Eficiência: ~6 GOPS/W                                     │
│                                                              │
│  ⚠️ Em termos absolutos, i7 é mais eficiente                │
│  ✅ Mas FPGA é viável sem sistema operacional               │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

---

## ❌ Quando o i7 VENCE Facilmente

### Cenário 1: CNNs Modernas e Grandes

| CNN | Operações | FPGA (estimado) | i7 (otimizado) |
|-----|-----------|-----------------|----------------|
| **AlexNet** | ~700M | ~100ms | ~5ms |
| **VGG-16** | ~15B | ~2s | ~30ms |
| **ResNet-50** | ~4B | ~600ms | ~15ms |
| **MobileNetV2** | ~300M | ~50ms | ~3ms |

### Cenário 2: Batch Processing

```
┌─────────────────────────────────────────────────────────────┐
│           THROUGHPUT COM BATCH SIZE = 32                     │
│                                                              │
│  FPGA Cyclone IV:                                            │
│  • Limitado pela memória SDRAM                              │
│  • Throughput: ~50-100 imagens/segundo                      │
│                                                              │
│  i7 com batch=32:                                            │
│  • Uso eficiente de cache e SIMD                            │
│  • Throughput: ~500-2000 imagens/segundo                    │
│                                                              │
│  🏆 i7 é 10-20x mais rápido                                 │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### Cenário 3: Frameworks Otimizados

O i7 com frameworks otimizados (ONNX Runtime, TensorRT, OpenVINO) tem vantagem massiva:

| Framework | Aceleração vs Python puro |
|-----------|---------------------------|
| **ONNX Runtime** | 2-5x |
| **OpenVINO** | 3-10x |
| **TensorRT** | 5-20x |

---

## 🔍 Análise do Claim de "350% de Speedup"

### O que o documento original afirma:

> "A placa DE2-115 fornece recursos lógicos abundantes para demonstrar ganhos de velocidade de até 350% em relação à execução puramente em software."

### Interpretação Correta

```
┌─────────────────────────────────────────────────────────────┐
│           O QUE SIGNIFICA 350% DE SPEEDUP?                   │
│                                                              │
│  350% de speedup = 3.5x mais rápido                         │
│                                                              │
│  Comparação provável:                                        │
│  ┌─────────────────────────────────────────────────────┐   │
│  │  Software no NEORV32 (soft-core RISC-V)             │   │
│  │  • Clock: 100 MHz                                   │   │
│  │  • Sem hardware dedicado                            │   │
│  │  • Execução serial                                  │   │
│  │  • Tempo: ~35ms para operação                       │   │
│  └─────────────────────────────────────────────────────┘   │
│                          vs                                  │
│  ┌─────────────────────────────────────────────────────┐   │
│  │  Hardware Acelerado (Matriz Sistólica)              │   │
│  │  • Clock: 100 MHz                                   │   │
│  │  • 64 PEs em paralelo                               │   │
│  │  • Processamento paralelo                           │   │
│  │  • Tempo: ~10ms para mesma operação                 │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                              │
│  ⚠️ NÃO é comparação com i7!                                │
│  ⚠️ É comparação: Soft-core vs Hardware dedicado           │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

---

## 📊 Comparação Realista

### Benchmark Hipotético: LeNet-5 no MNIST

| Sistema | Tempo de Inferência | Throughput (imgs/s) |
|---------|---------------------|---------------------|
| **NEORV32 (software)** | ~100ms | ~10 |
| **FPGA Acelerado** | ~1-5ms | ~200-1000 |
| **i7 Python (TensorFlow)** | ~2-5ms | ~200-500 |
| **i7 ONNX Runtime** | ~0.5-1ms | ~1000-2000 |
| **i7 OpenVINO** | ~0.2-0.5ms | ~2000-5000 |

### Conclusão Realista

```
┌─────────────────────────────────────────────────────────────┐
│           VERDADE SOBRE PERFORMANCE                          │
│                                                              │
│  FPGA vs NEORV32 (software no próprio FPGA):                │
│  ✅ FPGA acelerado é 3.5x-10x mais rápido                   │
│                                                              │
│  FPGA vs i7 Desktop:                                         │
│  ❌ i7 é geralmente 5-50x mais rápido                       │
│  ✅ FPGA pode vencer em LATÊNCIA (batch=1)                  │
│  ✅ FPGA vence em consumo energético (5W vs 65W+)           │
│  ✅ FPGA vence em determinismo temporal                     │
│                                                              │
│  Onde FPGA faz sentido:                                      │
│  • Sistemas embarcados                                       │
│  • Latência ultra-baixa                                      │
│  • Ambientes com restrição de energia                        │
│  • Processamento em tempo real                               │
│  • Prototipagem de aceleradores                              │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

---

## 🎯 Recomendação para o TCC

### Como Apresentar os Resultados

1. **Seja honesto sobre as limitações**
   - Não compare diretamente com i7 de desktop
   - Compare com o NEORV32 rodando software

2. **Destaque os pontos fortes do FPGA**
   - Latência determinística
   - Baixo consumo de energia
   - Paralelismo verdadeiro
   - Prototipagem de hardware

3. **Contextualize a contribuição**
   - O valor acadêmico está na **arquitetura**
   - Não na performance absoluta
   - Aceleradores FPGA modernos (Agilex, Versal) são muito mais rápidos

### Comparação Justa para o TCC

| Comparação | Métrica | Resultado |
|------------|---------|-----------|
| **NEORV32 software vs Acelerador** | Speedup | 3.5x-10x ✅ |
| **Consumo energético** | Eficiência | FPGA melhor ✅ |
| **Latência determinística** | Jitter | FPGA melhor ✅ |
| **Throughput absoluto** | GOPS | i7 melhor ❌ |

---

## 🏷️ Tags

#Performance #Comparison #FPGA #CPU #i7 #Benchmark #Throughput #Latency

---

**Veja também:**
- [[Systolic Array]] - Arquitetura do acelerador
- [[Clock Management]] - Métricas de throughput
- [[Publicação Científica]] - Análise de qualidade do trabalho
