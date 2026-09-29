// ================================================================================ //
// NEORV32 MNIST Inference (Fase 3/4 do TCC) - Driver do acelerador sistolico       //
// -------------------------------------------------------------------------------- //
// Ver accel_driver.h e o cabecalho de neorv32_systolic_wb_accelerator.vhd para o   //
// mapa de memoria e a semantica de calculo (RESULT = ACT_tile @ WEIGHT_tile).      //
// ================================================================================ //
#include "accel_driver.h"

#define ACCEL_CTRL   (*(volatile uint32_t*)(ACCEL_BASE + 0x000))
#define ACCEL_STATUS (*(volatile uint32_t*)(ACCEL_BASE + 0x004))

#define ACCEL_WEIGHT(word) (*(volatile uint32_t*)(ACCEL_BASE + 0x100 + ((word) << 2)))
#define ACCEL_ACT(word)    (*(volatile uint32_t*)(ACCEL_BASE + 0x500 + ((word) << 2)))
#define ACCEL_RESULT(word) (*(volatile uint32_t*)(ACCEL_BASE + 0x900 + ((word) << 2)))

static inline uint32_t pack4i8(int8_t b0, int8_t b1, int8_t b2, int8_t b3) {
    return ((uint32_t)(uint8_t)b0 << 0)  |
           ((uint32_t)(uint8_t)b1 << 8)  |
           ((uint32_t)(uint8_t)b2 << 16) |
           ((uint32_t)(uint8_t)b3 << 24);
}

// Escreve um tile 8x8 (64 bytes, row-major) na janela indicada (0x100 ou 0x500)
static void accel_load_tile(volatile uint32_t *base_macro_unused, uint32_t base_off, const int8_t tile[64]) {
    (void)base_macro_unused;
    for (int w = 0; w < 16; w++) {
        uint32_t v = pack4i8(tile[w*4+0], tile[w*4+1], tile[w*4+2], tile[w*4+3]);
        *(volatile uint32_t*)(ACCEL_BASE + base_off + (w << 2)) = v;
    }
}

static void accel_run_and_wait(void) {
    // A FSM do acelerador dispara na BORDA DE SUBIDA de CTRL[0], nao no nivel.
    // Escrever 0x1 repetidamente sem voltar a zero nao gera borda: a partir da
    // segunda chamada o array nunca mais iniciava, e o polling saia de imediato
    // pelo done anterior, devolvendo o resultado do tile anterior.
    ACCEL_CTRL = 0x0;
    ACCEL_CTRL = 0x1; // borda de subida -> start
    while ((ACCEL_STATUS & 0x2u) == 0u) {
        // STATUS[1] agora e o done da OPERACAO (tile 8x8 inteiro), nao o do
        // array, que pulsa a cada uma das 8 linhas -- ver o wrapper VHDL.
    }
    ACCEL_CTRL = 0x0; // deixa CTRL[0] baixo para a proxima borda
}

static void accel_read_result_tile(int32_t out[64]) {
    for (int w = 0; w < 64; w++) {
        out[w] = (int32_t)ACCEL_RESULT(w);
    }
}

void accel_matmul_i8(const int8_t *A, uint32_t M, uint32_t K,
                      const int8_t *W, uint32_t N,
                      int32_t zp_a,
                      int32_t *C) {
    int8_t atile[64];
    int8_t wtile[64];
    int32_t rtile[64];

    for (uint32_t m0 = 0; m0 < M; m0 += 8) {
        for (uint32_t n0 = 0; n0 < N; n0 += 8) {
            int32_t acc[8][8];
            int32_t wcolsum[8]; // soma de W[k][n] sobre TODO o K, por coluna n do tile de saida
            for (int i = 0; i < 8; i++) {
                wcolsum[i] = 0;
                for (int j = 0; j < 8; j++) acc[i][j] = 0;
            }

            for (uint32_t k0 = 0; k0 < K; k0 += 8) {

                for (int kl = 0; kl < 8; kl++) {
                    uint32_t k = k0 + kl;
                    for (int nl = 0; nl < 8; nl++) {
                        uint32_t n = n0 + nl;
                        int8_t wv = (k < K && n < N) ? W[k * N + n] : 0;
                        wtile[kl * 8 + nl] = wv;
                        wcolsum[nl] += (int32_t)wv;
                    }
                }

                for (int ml = 0; ml < 8; ml++) {
                    uint32_t m = m0 + ml;
                    for (int kl = 0; kl < 8; kl++) {
                        uint32_t k = k0 + kl;
                        atile[ml * 8 + kl] = (m < M && k < K) ? A[m * K + k] : 0;
                    }
                }

                accel_load_tile(0, 0x100, wtile);
                accel_load_tile(0, 0x500, atile);
                accel_run_and_wait();
                accel_read_result_tile(rtile);

                for (int ml = 0; ml < 8; ml++) {
                    for (int nl = 0; nl < 8; nl++) {
                        acc[ml][nl] += rtile[ml * 8 + nl];
                    }
                }
            }

            // Correcao de zero-point (quantizacao assimetrica): subtrai zp_a * soma(W[:,n])
            // ver TFLite INT8 quant spec -- equivalente a ter usado (A - zp_a) desde o inicio.
            for (int ml = 0; ml < 8; ml++) {
                uint32_t m = m0 + ml;
                if (m >= M) continue;
                for (int nl = 0; nl < 8; nl++) {
                    uint32_t n = n0 + nl;
                    if (n >= N) continue;
                    C[m * N + n] = acc[ml][nl] - zp_a * wcolsum[nl];
                }
            }
        }
    }
}
