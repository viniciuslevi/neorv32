// ================================================================================ //
// NEORV32 MNIST Inference (Fase 4 do TCC) - Pipeline de inferencia end-to-end      //
// ================================================================================ //
#ifndef INFERENCE_H
#define INFERENCE_H

#include <stdint.h>

// Roda a CNN completa (conv1 -> pool -> conv2 -> pool -> dense1 -> dense2) sobre a
// imagem 28x28 INT8 previamente carregada em SDRAM_OFF_INPUT. Retorna a classe
// prevista (0-9, argmax dos logits) e imprime, via UART0, o tempo (ciclos) gasto
// em cada camada (Metodologia 3.9: latencia/throughput por camada).
int run_inference(void);

// Compara, para um matmul 8x8x8 representativo, o tempo (ciclos) do calculo via
// acelerador sistolico contra uma implementacao MAC puramente em software na CPU
// (Metodologia 3.8, caso de teste 5: "Comparacao latencia: MAC em software vs
// acelerador, mesmo tile"). Imprime os resultados via UART0.
void bench_sw_vs_hw(void);

#endif // INFERENCE_H
