// ================================================================================ //
// NEORV32 MNIST Inference (Fase 3/4 do TCC) - Driver do acelerador sistolico       //
// -------------------------------------------------------------------------------- //
// Interface de baixo nivel com tcc_systolic_wb_accelerator.vhd (janela         //
// CTRL/STATUS/INFO/WEIGHT/ACT/RESULT) e multiplicacao de matrizes INT8 em tiles    //
// de ACCEL_TILE x ACCEL_TILE, com correcao de zero-point (quantizacao TFLite).     //
//                                                                                  //
// Dois jeitos de mover os dados ate o acelerador:                                  //
//   accel_matmul_i8   a CPU junta os bytes de cada tile e escreve word a word      //
//                     (layout linear, nenhum preparo; e o caminho original)        //
//   accel_*_dma       o DMA do NEORV32 copia tiles ja contiguos da memoria para    //
//                     o acelerador, um descritor por tile, e a CPU dorme (wfi)     //
//                     enquanto isso (Proposta A, "Proposta 16x16 + DMA")           //
// ================================================================================ //
#ifndef ACCEL_DRIVER_H
#define ACCEL_DRIVER_H

#include <stdint.h>

#define ACCEL_BASE 0x90000000u

// Tamanho do array, fixado na compilacao (make USER_FLAGS+=-DACCEL_TILE=16).
// accel_check() confere contra o registrador INFO do bitstream.
#ifndef ACCEL_TILE
#define ACCEL_TILE 8
#endif
#define ACCEL_TT (ACCEL_TILE * ACCEL_TILE)

// 0 se o acelerador tem ACCEL_TILE x ACCEL_TILE; senao, o valor lido de INFO
// ([7:0] linhas, [15:8] colunas).
uint32_t accel_check(void);

// ---------------------------------------------------------------------------------
// Caminho original: a CPU move os dados
// ---------------------------------------------------------------------------------
// Multiplica A(M x K) por W(K x N), ambos INT8, com zero-point de entrada zp_a
// (o peso W e assumido com zero-point 0, convencao padrao de quantizacao INT8
// do TFLite para pesos). Acumula em C (M x N), INT32, RAW (sem bias, sem
// requantizacao) -- isso e responsabilidade da camada acima (inference.c).
//
// A, W e C sao ponteiros para memoria linear (SDRAM ou SRAM interna):
//   A[m*K + k], W[k*N + n], C[m*N + n]
//
// M, K, N nao precisam ser multiplos do tile: os tiles de borda sao
// preenchidos com zero automaticamente.
void accel_matmul_i8(const int8_t *A, uint32_t M, uint32_t K,
                      const int8_t *W, uint32_t N,
                      int32_t zp_a,
                      int32_t *C);

// ---------------------------------------------------------------------------------
// Caminho com DMA: dados ja em tiles contiguos
// ---------------------------------------------------------------------------------
// Numero de tiles para cobrir n elementos
static inline uint32_t accel_tiles(uint32_t n) { return (n + ACCEL_TILE - 1u) / ACCEL_TILE; }

// Pesos empacotados: o tile (ni, ki) ocupa ACCEL_TT bytes contiguos em
// tiles + (ni*kt + ki)*ACCEL_TT, linha a linha (k, n) dentro do tile, com zero
// fora de K x N. colsum[n] = soma de W[k][n] sobre todo o K (para a correcao
// de zero-point), nt*ACCEL_TILE entradas. Montado uma vez por camada.
typedef struct {
    uint32_t K, N;
    uint32_t kt, nt;
    const int8_t  *tiles;
    const int32_t *colsum;
} accel_wpack_t;

// Bytes que accel_wpack grava em dst (tiles + colsum). dst alinhado a 4.
uint32_t accel_wpack_bytes(uint32_t K, uint32_t N);
void accel_wpack(const int8_t *W, uint32_t K, uint32_t N, void *dst, accel_wpack_t *out);

// Ativacoes empacotadas: o tile (mi, ki) ocupa ACCEL_TT bytes contiguos em
// dst + (mi*kt + ki)*ACCEL_TT, linha a linha (m, k), com zero fora de M x K.
// accel_apack_index da a posicao de A[m][k] nesse layout, para quem gera as
// ativacoes direto nele (im2col) sem passar pelo layout linear.
uint32_t accel_apack_bytes(uint32_t M, uint32_t K);
void accel_apack(const int8_t *A, uint32_t M, uint32_t K, int8_t *dst);
static inline uint32_t accel_apack_index(uint32_t m, uint32_t k, uint32_t kt) {
    return ((m / ACCEL_TILE) * kt + (k / ACCEL_TILE)) * ACCEL_TT
         + (m % ACCEL_TILE) * ACCEL_TILE + (k % ACCEL_TILE);
}

// Prepara o DMA: liga o modulo, habilita a IRQ do DMA em mie (para o wfi
// acordar) e garante mstatus.MIE = 0 (acorda sem desviar para um handler).
// Retorna 0 se o DMA existe no bitstream.
int accel_dma_init(void);

// 1 (padrao): enquanto o array calcula um tile, o DMA ja carrega os pesos do
// proximo; enquanto a CPU le RESULT, o DMA carrega as ativacoes do proximo.
// 0: um passo de cada vez (DMA, depois calculo, depois leitura), para medir.
void accel_dma_set_overlap(int on);

// C(M x N) = A @ W - zp_a * colsum, como accel_matmul_i8, com A em tiles
// (accel_apack) e W empacotado (accel_wpack). A.K = w->K.
void accel_matmul_dma(const int8_t *A_tiles, uint32_t M, const accel_wpack_t *w,
                      int32_t zp_a, int32_t *C);

// c(1 x N) = a @ W - zp_a * colsum para M = 1 (camadas dense): a e o vetor
// linear de K bytes, alinhado a 4. So a linha 0 de ACT e de RESULT e usada.
// Le ate kt*ACCEL_TILE bytes de a: o que passa de K multiplica linhas de peso
// zeradas, entao o conteudo dessa folga nao importa.
void accel_matvec_dma(const int8_t *a, const accel_wpack_t *w, int32_t zp_a, int32_t *c);

// Erros de barramento do DMA desde o boot (um access fault aborta o descritor;
// diferente da CPU, o DMA nao tem retry). Qualquer valor nao zero invalida o
// resultado.
uint32_t accel_dma_errors(void);

#endif // ACCEL_DRIVER_H
