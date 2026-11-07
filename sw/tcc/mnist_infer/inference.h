// ================================================================================ //
// NEORV32 MNIST Inference (Fase 4 do TCC) - Pipeline de inferencia end-to-end      //
// ================================================================================ //
#ifndef INFERENCE_H
#define INFERENCE_H

#include <stdint.h>

// Como os produtos de matrizes sao feitos
typedef enum {
    INFER_SW        = 0, // so na CPU                 (linhas "[bench-sw]",  "[logits-sw]")
    INFER_ACCEL_CPU = 1, // acelerador, a CPU move os dados (accel_matmul_i8;
                         //                            "[bench-cpu]", "[logits-cpu]")
    INFER_ACCEL_DMA = 2  // acelerador, o DMA move tiles contiguos (Proposta A;
                         //                            "[bench]",     "[logits]")
} infer_mode_t;

// Roda a CNN completa (conv1 -> pool -> conv2 -> pool -> dense1 -> dense2) sobre a
// imagem 28x28 INT8 previamente carregada em SDRAM_OFF_INPUT. Retorna a classe
// prevista (0-9, argmax dos logits) e imprime, via UART0, o tempo (ciclos) gasto
// em cada camada (Metodologia 3.9: latencia/throughput por camada). Os tres modos
// dao logits bit a bit identicos. logits recebe os 10 logits INT8 e total_cycles
// a soma dos ciclos das seis etapas (mtime: inclui o tempo da CPU dormindo).
// INFER_ACCEL_DMA monta os pesos em tiles na primeira chamada depois de cada 'W'
// (fora da medicao) e exige accel_dma_init().
int run_inference(infer_mode_t mode, int8_t *logits, uint32_t *total_cycles);

// Compara, para um matmul TxTxT representativo (T = ACCEL_TILE), o tempo (ciclos) do calculo via
// acelerador sistolico contra uma implementacao MAC puramente em software na CPU
// (Metodologia 3.8, caso de teste 5: "Comparacao latencia: MAC em software vs
// acelerador, mesmo tile"). Imprime os resultados via UART0.
void bench_sw_vs_hw(void);

#endif // INFERENCE_H
