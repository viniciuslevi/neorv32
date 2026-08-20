# HLS Design Flow - Fluxo de Design com High-Level Synthesis

> **Conversão de Modelos de Machine Learning para Hardware**

---

## 📋 Visão Geral

O **HLS (High-Level Synthesis)** permite converter algoritmos descritos em linguagens de alto nível (C/C++) para código HDL (VHDL/Verilog). Para o TCC, o HLS é fundamental para transformar modelos treinados em Python para hardware executável no FPGA.

### 🔗 Links Relacionados
- [[Home]] - Página principal
- [[FPGA AI Suite Analysis]] - Por que não usar AI Suite
- [[Systolic Array]] - Arquitetura do acelerador

---

## 🔄 Pipeline de Design

### Visão Geral

```
┌─────────────────────────────────────────────────────────────┐
│           PIPELINE COMPLETO DE DESIGN                        │
│                                                              │
│  ┌──────────────┐                                            │
│  │   FASE 1     │  Treinamento do Modelo                     │
│  │              │                                            │
│  │  Python +    │  • Definir arquitetura                     │
│  │  TensorFlow  │  • Treinar modelo                          │
│  │  Keras       │  • Validar acurácia                        │
│  │  PyTorch     │  • Quantizar para INT8                     │
│  └──────┬───────┘                                            │
│         │                                                    │
│         ▼                                                    │
│  ┌──────────────┐                                            │
│  │   FASE 2     │  Conversão para HLS                        │
│  │              │                                            │
│  │  hls4ml ou   │  • Exportar modelo                         │
│  │  Intel HLS   │  • Converter para C++                      │
│  │  Compiler    │  • Otimizar para FPGA                      │
│  └──────┬───────┘                                            │
│         │                                                    │
│         ▼                                                    │
│  ┌──────────────┐                                            │
│  │   FASE 3     │  Síntese HLS                               │
│  │              │                                            │
│  │  HLS Tool    │  • Scheduling                              │
│  │              │  • Pipelining                              │
│  │              │  • Geração de RTL                          │
│  └──────┬───────┘                                            │
│         │                                                    │
│         ▼                                                    │
│  ┌──────────────┐                                            │
│  │   FASE 4     │  Síntese Lógica                            │
│  │              │                                            │
│  │  Quartus     │  • Síntese RTL                             │
│  │  Prime       │  • Place & Route                           │
│  │              │  • Timing Analysis                         │
│  └──────┬───────┘                                            │
│         │                                                    │
│         ▼                                                    │
│  ┌──────────────┐                                            │
│  │   FASE 5     │  Validação                                 │
│  │              │                                            │
│  │  DE2-115     │  • Programar FPGA                          │
│  │              │  • Testes funcionais                       │
│  │              │  • Medição de performance                  │
│  └──────────────┘                                            │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

---

## 🐍 Fase 1: Treinamento do Modelo

### Frameworks Suportados

| Framework | Suporte | Recomendação |
|-----------|---------|--------------|
| **TensorFlow/Keras** | Excelente | ⭐ Recomendado |
| **PyTorch** | Bom | ⭐ Alternativa |
| **ONNX** | Bom | Para interoperabilidade |

### Exemplo de Modelo para MNIST

```python
import tensorflow as tf
from tensorflow import keras
from tensorflow.keras import layers

# Definir modelo
model = keras.Sequential([
    layers.Conv2D(32, (3, 3), activation='relu', input_shape=(28, 28, 1)),
    layers.MaxPooling2D((2, 2)),
    layers.Conv2D(64, (3, 3), activation='relu'),
    layers.MaxPooling2D((2, 2)),
    layers.Flatten(),
    layers.Dense(64, activation='relu'),
    layers.Dense(10, activation='softmax')
])

# Compilar
model.compile(
    optimizer='adam',
    loss='sparse_categorical_crossentropy',
    metrics=['accuracy']
)

# Treinar
model.fit(x_train, y_train, epochs=5, validation_split=0.1)

# Salvar
model.save('mnist_model.h5')
```

### Quantização para INT8

```python
import tensorflow as tf

# Carregar modelo
model = tf.keras.models.load_model('mnist_model.h5')

# Converter para TFLite com quantização
converter = tf.lite.TFLiteConverter.from_keras_model(model)
converter.optimizations = [tf.lite.Optimize.DEFAULT]
converter.target_spec.supported_ops = [tf.lite.OpsSet.TFLITE_BUILTINS_INT8]
converter.inference_input_type = tf.int8
converter.inference_output_type = tf.int8

# Dataset de calibração
def representative_dataset():
    for data in x_test[:100]:
        yield [data.reshape(1, 28, 28, 1)]

converter.representative_dataset = representative_dataset

# Converter
quantized_model = converter.convert()

# Salvar
with open('mnist_model_int8.tflite', 'wb') as f:
    f.write(quantized_model)
```

---

## 🔧 Fase 2: Conversão com hls4ml

### O que é hls4ml?

**hls4ml** é uma ferramenta open-source desenvolvida pelo CERN e colaboradores para converter modelos de machine learning em código HDL usando HLS.

### Instalação

```bash
pip install hls4ml
```

### Conversão Básica

```python
import hls4ml
import tensorflow as tf

# Carregar modelo
model = tf.keras.models.load_model('mnist_model.h5')

# Configurar para Cyclone IV
config = hls4ml.utils.config_from_keras_model(
    model, 
    granularity='model',
    backend='Quartus'
)

# Ajustar para INT8
config['Model']['Precision'] = 'ap_int<8>'
config['Model']['ReuseFactor'] = 1

# Converter
hls_model = hls4ml.converters.convert_from_keras_model(
    model,
    hls_config=config,
    output_dir='hls4ml_project',
    backend='Quartus',
    io_type='io_stream',
    fpga_part='EP4CE115F29C7'  # Cyclone IV E
)

# Compilar
hls_model.compile()

# Visualizar
hls4ml.utils.plot_model(hls_model, show_shapes=True, show_precision=True)
```

### Configurações Importantes

```python
config = {
    'Model': {
        'Precision': 'ap_int<8>',
        'ReuseFactor': 1,
        'Strategy': 'Latency'  # ou 'Resource'
    },
    'LayerName': {
        'conv2d': {
            'Precision': {
                'result': 'ap_int<16>',
                'weight': 'ap_int<8>'
            }
        }
    }
}
```

### Estratégias de Síntese

| Estratégia | Descrição | Quando Usar |
|------------|-----------|-------------|
| **Latency** | Minimiza latência | Baixa latência crítica |
| **Resource** | Minimiza recursos | Recursos limitados |

---

## 🛠️ Fase 2 Alternativa: Intel HLS Compiler

### O que é

O **Intel HLS Compiler** é a ferramenta oficial da Intel para síntese de alto nível, integrada ao Quartus Prime.

### Estrutura de Projeto

```
hls_project/
├── src/
│   ├── component.cpp    # Código do componente
│   └── component.h      # Headers
├── testbench/
│   └── test.cpp         # Testbench
└── CMakeLists.txt       # Build
```

### Exemplo de Componente HLS

```cpp
// component.cpp
#include <hls_stream.h>
#include <ap_int.h>

typedef ap_int<8> int8_t;
typedef ap_int<16> int16_t;
typedef ap_int<32> int32_t;

// Convolução 3x3
void conv2d_3x3(
    hls::stream<int8_t> &input,
    int8_t weights[3][3],
    hls::stream<int16_t> &output,
    int height,
    int width
) {
    #pragma HLS INTERFACE axis port=input
    #pragma HLS INTERFACE axis port=output
    #pragma HLS INTERFACE ap_ctrl_none port=return
    
    int16_t sum;
    int8_t window[3][3];
    
    #pragma HLS ARRAY_PARTITION variable=window complete dim=0
    #pragma HLS ARRAY_PARTITION variable=weights complete dim=0
    
    for (int i = 0; i < height - 2; i++) {
        for (int j = 0; j < width - 2; j++) {
            #pragma HLS PIPELINE II=1
            
            // Carregar janela
            for (int ki = 0; ki < 3; ki++) {
                for (int kj = 0; kj < 3; kj++) {
                    window[ki][kj] = input.read();
                }
            }
            
            // Calcular convolução
            sum = 0;
            for (int ki = 0; ki < 3; ki++) {
                for (int kj = 0; kj < 3; kj++) {
                    sum += window[ki][kj] * weights[ki][kj];
                }
            }
            
            output.write(sum);
        }
    }
}
```

### Pragmas HLS Importantes

| Pragma | Função | Exemplo |
|--------|--------|---------|
| `PIPELINE` | Paralelismo de instrução | `#pragma HLS PIPELINE II=1` |
| `ARRAY_PARTITION` | Divide arrays | `#pragma HLS ARRAY_PARTITION complete` |
| `UNROLL` | Desenrola loops | `#pragma HLS UNROLL factor=4` |
| `INLINE` | Inline de funções | `#pragma HLS INLINE` |

### Compilação

```bash
# Compilar componente
i++ -march= Cyclone10GX --component src/component.cpp

# Gerar RTL
i++ -march=Cyclone10GX src/component.cpp -o output
```

---

## 📊 Fase 3: Síntese HLS

### Processo de Síntese

```
┌─────────────────────────────────────────────────────────────┐
│           SÍNTESE HLS                                        │
│                                                              │
│  Código C/C++                                                │
│       │                                                      │
│       ▼                                                      │
│  ┌─────────────┐                                            │
│  │  Front-end  │  Parsing e análise                         │
│  └──────┬──────┘                                            │
│         │                                                    │
│         ▼                                                    │
│  ┌─────────────┐                                            │
│  │ Scheduling  │  Atribuir operações a ciclos               │
│  └──────┬──────┘                                            │
│         │                                                    │
│         ▼                                                    │
│  ┌─────────────┐                                            │
│  │  Binding    │  Mapear para recursos                      │
│  └──────┬──────┘                                            │
│         │                                                    │
│         ▼                                                    │
│  ┌─────────────┐                                            │
│  │ Allocation  │  Alocar unidades funcionais                │
│  └──────┬──────┘                                            │
│         │                                                    │
│         ▼                                                    │
│  RTL (VHDL/Verilog)                                          │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### Métricas de Síntese

| Métrica | Descrição |
|---------|-----------|
| **Latency** | Ciclos para completar |
| **II (Initiation Interval)** | Ciclos entre entradas |
| **DSP** | Blocos DSP utilizados |
| **FF** | Flip-flops utilizados |
| **LUT** | LUTs utilizadas |
| **BRAM** | Blocos de memória |

---

## 🔨 Fase 4: Síntese com Quartus Prime

### Integração com Quartus

```
┌─────────────────────────────────────────────────────────────┐
│           FLUXO NO QUARTUS PRIME                             │
│                                                              │
│  1. Criar Projeto                                            │
│     └── File → New Project Wizard                            │
│                                                              │
│  2. Adicionar RTL gerado                                     │
│     └── Project → Add/Remove Files in Project                │
│                                                              │
│  3. Configurar Device                                        │
│     └── Device: EP4CE115F29C7                                │
│                                                              │
│  4. Configurar Timing                                        │
│     └── SDC constraints                                      │
│                                                              │
│  5. Analisar & Sintetizar                                    │
│     └── Processing → Start → Analysis & Synthesis            │
│                                                              │
│  6. Fitter (Place & Route)                                   │
│     └── Processing → Start → Fitter                          │
│                                                              │
│  7. Timing Analysis                                          │
│     └── Tools → TimeQuest Timing Analyzer                    │
│                                                              │
│  8. Programar FPGA                                           │
│     └── Tools → Programmer                                   │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### Constraints (SDC)

```tcl
# Clock principal
create_clock -name clk -period 10.000 [get_ports clk]

# Clock de 100MHz (10ns período)

# False paths para resets
set_false_path -from [get_ports reset]

# Multicycle paths
set_multicycle_path -setup 2 -from [get_registers *acc*]
```

---

## ✅ Fase 5: Validação

### Testbench em C++

```cpp
// test.cpp
#include <iostream>
#include "component.h"

int main() {
    hls::stream<int8_t> input;
    hls::stream<int16_t> output;
    int8_t weights[3][3] = {{1, 0, -1}, {2, 0, -2}, {1, 0, -1}};
    
    // Carregar dados de teste
    for (int i = 0; i < 9; i++) {
        input.write(i);
    }
    
    // Executar
    conv2d_3x3(input, weights, output, 3, 3);
    
    // Verificar saída
    int16_t result = output.read();
    std::cout << "Result: " << result << std::endl;
    
    return 0;
}
```

### Validação no FPGA

1. **Co-simulação**: Validar RTL vs C++
2. **Hardware em Loop**: Testar no FPGA real
3. **Comparação de Resultados**: Verificar acurácia

---

## 📚 Comparação de Ferramentas

| Característica | hls4ml | Intel HLS Compiler |
|----------------|--------|-------------------|
| **Licença** | Open Source | Proprietária |
| **Integração ML** | Nativa | Manual |
| **Suporte Cyclone IV** | Indireto | Bom |
| **Curva de Aprendizado** | Baixa | Média |
| **Documentação** | Boa | Excelente |

---

## 🎯 Recomendação para o TCC

### Abordagem Recomendada

```
┌─────────────────────────────────────────────────────────────┐
│           FLUXO RECOMENDADO                                  │
│                                                              │
│  1. Treinar modelo em Python/Keras                           │
│     └── Fácil e rápido                                       │
│                                                              │
│  2. Quantizar para INT8                                      │
│     └── Otimização para FPGA                                 │
│                                                              │
│  3. Converter com hls4ml                                     │
│     └── Geração automática de RTL                            │
│                                                              │
│  4. Refinar com Intel HLS (se necessário)                    │
│     └── Otimizações específicas                              │
│                                                              │
│  5. Sintetizar com Quartus                                   │
│     └── Implementação final                                  │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

---

## 📚 Referências

- [hls4ml Documentation](https://fastmachinelearning.org/hls4ml/)
- [Intel HLS Compiler User Guide](https://www.intel.com/content/www/us/en/docs/programmable/683623/current/overview.html)
- [TensorFlow Model Optimization](https://www.tensorflow.org/model_optimization)

---

## 🏷️ Tags

#HLS #hls4ml #IntelHLS #DesignFlow #Python #Keras #TensorFlow #Quantization #INT8

---

**Veja também:**
- [[FPGA AI Suite Analysis]] - Por que não usar AI Suite
- [[Systolic Array]] - Arquitetura do acelerador
- [[Implementation Matrix]] - Visão geral da implementação
