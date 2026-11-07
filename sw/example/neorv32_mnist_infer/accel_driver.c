// ================================================================================ //
// NEORV32 MNIST Inference (Fase 3/4 do TCC) - Driver do acelerador sistolico       //
// -------------------------------------------------------------------------------- //
// Ver accel_driver.h e o cabecalho de neorv32_systolic_wb_accelerator.vhd para o   //
// mapa de memoria e a semantica de calculo (RESULT = ACT_tile @ WEIGHT_tile).      //
// ================================================================================ //
#include "accel_driver.h"
#include <neorv32.h>

#define ACCEL_CTRL   (*(volatile uint32_t*)(ACCEL_BASE + 0x000))
#define ACCEL_STATUS (*(volatile uint32_t*)(ACCEL_BASE + 0x004))
#define ACCEL_INFO   (*(volatile uint32_t*)(ACCEL_BASE + 0x00C))

#define ACCEL_WEIGHT_ADDR (ACCEL_BASE + 0x100)
#define ACCEL_ACT_ADDR    (ACCEL_BASE + 0x500)
#define ACCEL_RESULT(word) (*(volatile uint32_t*)(ACCEL_BASE + 0x900 + ((word) << 2)))

#define T  ACCEL_TILE
#define TW (ACCEL_TT / 4) // words de 32 bits num tile INT8

uint32_t accel_check(void) {
    uint32_t info = ACCEL_INFO;
    if ((info & 0xFFFFu) == ((uint32_t)T | ((uint32_t)T << 8))) {
        return 0;
    }
    // bitstream anterior ao registrador INFO le 0 nesse endereco
    return (info == 0u) ? 0xFFFFFFFFu : info;
}

static inline uint32_t pack4i8(int8_t b0, int8_t b1, int8_t b2, int8_t b3) {
    return ((uint32_t)(uint8_t)b0 << 0)  |
           ((uint32_t)(uint8_t)b1 << 8)  |
           ((uint32_t)(uint8_t)b2 << 16) |
           ((uint32_t)(uint8_t)b3 << 24);
}

// A FSM do acelerador dispara na BORDA DE SUBIDA de CTRL[0], nao no nivel.
// Escrever 0x1 repetidamente sem voltar a zero nao gera borda: a partir da
// segunda chamada o array nunca mais iniciava, e o polling saia de imediato
// pelo done anterior, devolvendo o resultado do tile anterior.
static inline void accel_start(void) {
    ACCEL_CTRL = 0x0;
    ACCEL_CTRL = 0x1; // borda de subida -> start
}

// STATUS[1] e o done da OPERACAO (tile inteiro), nao o do array, que pulsa a
// cada linha -- ver o wrapper VHDL.
static inline void accel_wait(void) {
    while ((ACCEL_STATUS & 0x2u) == 0u) {
    }
}

// =================================================================================
// Caminho original: a CPU move os dados
// =================================================================================

// Escreve um tile TxT (row-major) na janela indicada (0x100 ou 0x500)
static void accel_load_tile(uint32_t base_off, const int8_t tile[ACCEL_TT]) {
    for (int w = 0; w < TW; w++) {
        uint32_t v = pack4i8(tile[w*4+0], tile[w*4+1], tile[w*4+2], tile[w*4+3]);
        *(volatile uint32_t*)(ACCEL_BASE + base_off + (w << 2)) = v;
    }
}

void accel_matmul_i8(const int8_t *A, uint32_t M, uint32_t K,
                      const int8_t *W, uint32_t N,
                      int32_t zp_a,
                      int32_t *C) {
    int8_t atile[ACCEL_TT];
    int8_t wtile[ACCEL_TT];

    for (uint32_t m0 = 0; m0 < M; m0 += T) {
        for (uint32_t n0 = 0; n0 < N; n0 += T) {
            int32_t acc[T][T];
            int32_t wcolsum[T]; // soma de W[k][n] sobre TODO o K, por coluna n do tile de saida
            for (int i = 0; i < T; i++) {
                wcolsum[i] = 0;
                for (int j = 0; j < T; j++) acc[i][j] = 0;
            }

            for (uint32_t k0 = 0; k0 < K; k0 += T) {

                for (int kl = 0; kl < T; kl++) {
                    uint32_t k = k0 + kl;
                    for (int nl = 0; nl < T; nl++) {
                        uint32_t n = n0 + nl;
                        int8_t wv = (k < K && n < N) ? W[k * N + n] : 0;
                        wtile[kl * T + nl] = wv;
                        wcolsum[nl] += (int32_t)wv;
                    }
                }

                for (int ml = 0; ml < T; ml++) {
                    uint32_t m = m0 + ml;
                    for (int kl = 0; kl < T; kl++) {
                        uint32_t k = k0 + kl;
                        atile[ml * T + kl] = (m < M && k < K) ? A[m * K + k] : 0;
                    }
                }

                accel_load_tile(0x100, wtile);
                accel_load_tile(0x500, atile);
                accel_start();
                accel_wait();
                ACCEL_CTRL = 0x0; // deixa CTRL[0] baixo para a proxima borda

                for (int ml = 0; ml < T; ml++) {
                    for (int nl = 0; nl < T; nl++) {
                        acc[ml][nl] += (int32_t)ACCEL_RESULT(ml * T + nl);
                    }
                }
            }

            // Correcao de zero-point (quantizacao assimetrica): subtrai zp_a * soma(W[:,n])
            // ver TFLite INT8 quant spec -- equivalente a ter usado (A - zp_a) desde o inicio.
            for (int ml = 0; ml < T; ml++) {
                uint32_t m = m0 + ml;
                if (m >= M) continue;
                for (int nl = 0; nl < T; nl++) {
                    uint32_t n = n0 + nl;
                    if (n >= N) continue;
                    C[m * N + n] = acc[ml][nl] - zp_a * wcolsum[nl];
                }
            }
        }
    }
}

// =================================================================================
// Empacotamento em tiles contiguos
// =================================================================================

uint32_t accel_wpack_bytes(uint32_t K, uint32_t N) {
    uint32_t kt = accel_tiles(K), nt = accel_tiles(N);
    return nt * kt * ACCEL_TT + nt * T * (uint32_t)sizeof(int32_t);
}

// Monta cada tile num buffer local e grava em words: o destino costuma ser a
// SDRAM, onde cada acesso custa um ciclo ACTIVE/READ|WRITE/PRECHARGE inteiro.
void accel_wpack(const int8_t *W, uint32_t K, uint32_t N, void *dst, accel_wpack_t *out) {
    uint32_t kt = accel_tiles(K), nt = accel_tiles(N);
    int8_t  *tiles  = (int8_t*)dst;
    int32_t *colsum = (int32_t*)(tiles + nt * kt * ACCEL_TT);
    union { int8_t b[ACCEL_TT]; uint32_t w[TW]; } buf;

    for (uint32_t ni = 0; ni < nt; ni++) {
        int32_t cs[T];
        for (int nl = 0; nl < T; nl++) cs[nl] = 0;
        for (uint32_t ki = 0; ki < kt; ki++) {
            for (int kl = 0; kl < T; kl++) {
                uint32_t k = ki * T + kl;
                for (int nl = 0; nl < T; nl++) {
                    uint32_t n = ni * T + nl;
                    int8_t v = (k < K && n < N) ? W[k * N + n] : 0;
                    buf.b[kl * T + nl] = v;
                    cs[nl] += v;
                }
            }
            uint32_t *d = (uint32_t*)(tiles + (ni * kt + ki) * ACCEL_TT);
            for (int w = 0; w < TW; w++) d[w] = buf.w[w];
        }
        for (int nl = 0; nl < T; nl++) colsum[ni * T + nl] = cs[nl];
    }

    out->K = K;
    out->N = N;
    out->kt = kt;
    out->nt = nt;
    out->tiles = tiles;
    out->colsum = colsum;
}

uint32_t accel_apack_bytes(uint32_t M, uint32_t K) {
    return accel_tiles(M) * accel_tiles(K) * ACCEL_TT;
}

void accel_apack(const int8_t *A, uint32_t M, uint32_t K, int8_t *dst) {
    uint32_t mt = accel_tiles(M), kt = accel_tiles(K);
    union { int8_t b[ACCEL_TT]; uint32_t w[TW]; } buf;

    for (uint32_t mi = 0; mi < mt; mi++) {
        for (uint32_t ki = 0; ki < kt; ki++) {
            for (int ml = 0; ml < T; ml++) {
                uint32_t m = mi * T + ml;
                for (int kl = 0; kl < T; kl++) {
                    uint32_t k = ki * T + kl;
                    buf.b[ml * T + kl] = (m < M && k < K) ? A[m * K + k] : 0;
                }
            }
            uint32_t *d = (uint32_t*)(dst + (mi * kt + ki) * ACCEL_TT);
            for (int w = 0; w < TW; w++) d[w] = buf.w[w];
        }
    }
}

// =================================================================================
// Caminho com DMA
// =================================================================================

static volatile uint32_t dma_error_count = 0;
static int dma_overlap = 1;

#define DMA_CTRL_EN_BIT    (1u << DMA_CTRL_EN)
#define DMA_CONF_WORDS(n)  ((uint32_t)(n) | DMA_SRC_INC_WORD | DMA_DST_INC_WORD)

int accel_dma_init(void) {
    if (neorv32_dma_available() == 0) {
        return -1;
    }
    // O wfi acorda com qualquer IRQ habilitada em mie mesmo com mstatus.MIE = 0,
    // e sem MIE nao ha desvio para handler: a execucao segue depois do wfi.
    neorv32_cpu_csr_clr(CSR_MSTATUS, 1u << CSR_MSTATUS_MIE);
    NEORV32_DMA->CTRL = 0;               // desliga: esvazia a fila de descritores
    NEORV32_DMA->CTRL = DMA_CTRL_EN_BIT;
    neorv32_cpu_csr_set(CSR_MIE, 1u << DMA_FIRQ_ENABLE);
    return 0;
}

void accel_dma_set_overlap(int on) {
    dma_overlap = on;
}

uint32_t accel_dma_errors(void) {
    return dma_error_count;
}

// Enfileira uma copia de n words de src para dst. A fila tem 16 entradas
// (IO_DMA_DSC_FIFO no top-level) e o driver nunca enfileira mais de 2
// descritores (6 entradas) antes de esperar, entao nao precisa conferir DFULL.
static inline void dma_copy(uint32_t src, uint32_t dst, uint32_t n) {
    NEORV32_DMA->DESC = src;
    NEORV32_DMA->DESC = dst;
    NEORV32_DMA->DESC = DMA_CONF_WORDS(n);
}

// Escrever START tambem zera DONE e ERROR.
static inline void dma_start(void) {
    NEORV32_DMA->CTRL = DMA_CTRL_EN_BIT | (1u << DMA_CTRL_START);
}

// Dorme ate o DMA terminar. Sem corrida entre a leitura de CTRL e o wfi: a IRQ
// do DMA e o proprio bit DONE (nivel), entao se o DMA terminar nesse meio
// tempo o wfi volta na hora. Nao fazer polling de CTRL: a CPU tem prioridade
// fixa no switch de barramento, e cada leitura atrasaria o proprio DMA.
static void dma_wait(void) {
    uint32_t ctrl;
    while (1) {
        ctrl = NEORV32_DMA->CTRL;
        if (ctrl & (1u << DMA_CTRL_DONE)) break;
        neorv32_cpu_sleep();
    }
    if (ctrl & (1u << DMA_CTRL_ERROR)) {
        // um erro de barramento aborta o descritor corrente; os seguintes
        // ficariam na fila e rodariam no proximo start com dados velhos
        dma_error_count++;
        NEORV32_DMA->CTRL = 0;
    }
    NEORV32_DMA->CTRL = DMA_CTRL_EN_BIT | (1u << DMA_CTRL_ACK); // baixa DONE e a IRQ
}

static inline void acc_add_tile(int32_t acc[T][T], int first) {
    for (int ml = 0; ml < T; ml++) {
        for (int nl = 0; nl < T; nl++) {
            int32_t r = (int32_t)ACCEL_RESULT(ml * T + nl);
            acc[ml][nl] = first ? r : acc[ml][nl] + r;
        }
    }
}

static void store_tile(const int32_t acc[T][T], uint32_t m0, uint32_t M, uint32_t n0,
                       uint32_t N, int32_t zp_a, const int32_t *colsum, int32_t *C) {
    for (int ml = 0; ml < T; ml++) {
        uint32_t m = m0 + ml;
        if (m >= M) break;
        for (int nl = 0; nl < T; nl++) {
            uint32_t n = n0 + nl;
            if (n >= N) break;
            C[m * N + n] = acc[ml][nl] - zp_a * colsum[n];
        }
    }
}

void accel_matmul_dma(const int8_t *A_tiles, uint32_t M, const accel_wpack_t *w,
                      int32_t zp_a, int32_t *C) {
    const uint32_t kt = w->kt, nt = w->nt, mt = accel_tiles(M);
    const uint32_t total = mt * nt * kt; // tiles na ordem (mi, ni, ki), ki mais interno
    int32_t acc[T][T];

    // endereco do tile i dessa sequencia, para pesos e para ativacoes
    #define W_TILE(i) ((uint32_t)(w->tiles + ((((i) / kt) % nt) * kt + (i) % kt) * ACCEL_TT))
    #define A_TILE(i) ((uint32_t)(A_tiles + (((i) / (kt * nt)) * kt + (i) % kt) * ACCEL_TT))

    if (total == 0) return;

    if (!dma_overlap) {
        for (uint32_t i = 0; i < total; i++) {
            uint32_t ki = i % kt;
            dma_copy(W_TILE(i), ACCEL_WEIGHT_ADDR, TW);
            dma_copy(A_TILE(i), ACCEL_ACT_ADDR, TW);
            dma_start();
            dma_wait();
            accel_start();
            accel_wait();
            acc_add_tile(acc, ki == 0);
            if (ki == kt - 1) {
                uint32_t ni = (i / kt) % nt, mi = i / (kt * nt);
                store_tile(acc, mi * T, M, ni * T, w->N, zp_a, w->colsum, C);
            }
        }
        return;
    }

    // Com sobreposicao. Invariante no topo do laco: WEIGHT e ACT ja tem o tile i.
    dma_copy(W_TILE(0), ACCEL_WEIGHT_ADDR, TW);
    dma_copy(A_TILE(0), ACCEL_ACT_ADDR, TW);
    dma_start();
    dma_wait();

    for (uint32_t i = 0; i < total; i++) {
        uint32_t ki = i % kt;
        int more = (i + 1 < total);

        accel_start();
        // O array copia os pesos no ciclo seguinte ao start: WEIGHT ja pode
        // receber o proximo tile enquanto ele calcula. ACT nao (lido linha a
        // linha ate o fim). Primeiro dorme no DMA, depois confere o array, para
        // nao disputar o barramento com o DMA fazendo polling de STATUS.
        if (more) {
            dma_copy(W_TILE(i + 1), ACCEL_WEIGHT_ADDR, TW);
            dma_start();
            dma_wait();
        }
        accel_wait();

        // Ativacoes do proximo tile enquanto a CPU le e acumula RESULT
        if (more) {
            dma_copy(A_TILE(i + 1), ACCEL_ACT_ADDR, TW);
            dma_start();
        }
        acc_add_tile(acc, ki == 0);
        if (ki == kt - 1) {
            uint32_t ni = (i / kt) % nt, mi = i / (kt * nt);
            store_tile(acc, mi * T, M, ni * T, w->N, zp_a, w->colsum, C);
        }
        if (more) {
            dma_wait();
        }
    }

    #undef W_TILE
    #undef A_TILE
}

void accel_matvec_dma(const int8_t *a, const accel_wpack_t *w, int32_t zp_a, int32_t *c) {
    const uint32_t kt = w->kt, nt = w->nt;
    const uint32_t total = nt * kt;
    int32_t acc[T];

    // Pesos do tile i e o pedaco de a que ele multiplica (linha 0 de ACT)
    #define W_TILE(i) ((uint32_t)(w->tiles + (i) * ACCEL_TT)) // (ni, ki) ja e i = ni*kt + ki
    #define A_ROW(i)  ((uint32_t)(a + ((i) % kt) * T))

    if (total == 0) return;

    // As linhas 1..T-1 de ACT ficam com lixo de antes: viram linhas 1..T-1 de
    // RESULT, que nao sao lidas.
    dma_copy(W_TILE(0), ACCEL_WEIGHT_ADDR, TW);
    dma_copy(A_ROW(0), ACCEL_ACT_ADDR, T / 4);
    dma_start();
    dma_wait();

    for (uint32_t i = 0; i < total; i++) {
        uint32_t ki = i % kt;
        int more = (i + 1 < total);

        accel_start();
        if (more && dma_overlap) {
            // A linha 0 de ACT e consumida logo no inicio da operacao, e o DMA
            // so chega a ela depois de copiar o tile de pesos inteiro.
            dma_copy(W_TILE(i + 1), ACCEL_WEIGHT_ADDR, TW);
            dma_copy(A_ROW(i + 1), ACCEL_ACT_ADDR, T / 4);
            dma_start();
            dma_wait();
        }
        accel_wait();

        for (int nl = 0; nl < T; nl++) {
            int32_t r = (int32_t)ACCEL_RESULT(nl);
            acc[nl] = (ki == 0) ? r : acc[nl] + r;
        }
        if (ki == kt - 1) {
            uint32_t n0 = (i / kt) * T;
            for (int nl = 0; nl < T; nl++) {
                uint32_t n = n0 + nl;
                if (n >= w->N) break;
                c[n] = acc[nl] - zp_a * w->colsum[n];
            }
        }
        if (more && !dma_overlap) {
            dma_copy(W_TILE(i + 1), ACCEL_WEIGHT_ADDR, TW);
            dma_copy(A_ROW(i + 1), ACCEL_ACT_ADDR, T / 4);
            dma_start();
            dma_wait();
        }
    }

    #undef W_TILE
    #undef A_ROW
}
