// ================================================================================ //
// NEORV32 MNIST Inference (Fase 4 do TCC) - Pipeline de inferencia end-to-end      //
// -------------------------------------------------------------------------------- //
// Implementa a CNN quantizada (ver ia_models/src/train.py e quantize.py) como uma  //
// sequencia de camadas conv2d (via im2col + acelerador sistolico), max-pooling     //
// (software) e fully-connected (via acelerador), seguindo exatamente os offsets e  //
// parametros de quantizacao gerados por export_weights.py em model_meta.h.         //
// ================================================================================ //
#include "inference.h"
#include "lcd.h"
#include "accel_driver.h"
#include "sdram.h"
#include "model_meta.h"
#include <neorv32.h>

// ---------------------------------------------------------------------------------
// im2col: converte um tile HxWxC (padding "same", kernel 3x3, stride 1) em uma
// matriz (H*W) x (9*C). Ordem do eixo K = (dy, dx, cin), dy mais externo -- DEVE
// bater com export_weights.py (kernel.transpose(1,2,3,0).reshape(9*Cin, Cout)).
// Posicoes fora da borda recebem o zero-point de entrada (representa valor real 0).
// ---------------------------------------------------------------------------------
static void build_im2col(const int8_t *in_hwc, uint32_t H, uint32_t W, uint32_t C,
                          int8_t in_zp, int8_t *im2col) {
    uint32_t K = 9u * C;
    for (uint32_t oh = 0; oh < H; oh++) {
        for (uint32_t ow = 0; ow < W; ow++) {
            int8_t *row = im2col + (size_t)(oh * W + ow) * K;
            uint32_t idx = 0;
            for (int dy = 0; dy < 3; dy++) {
                int32_t ih = (int32_t)oh + dy - 1;
                for (int dx = 0; dx < 3; dx++) {
                    int32_t iw = (int32_t)ow + dx - 1;
                    for (uint32_t c = 0; c < C; c++) {
                        int8_t v;
                        if (ih < 0 || ih >= (int32_t)H || iw < 0 || iw >= (int32_t)W) {
                            v = in_zp;
                        } else {
                            v = in_hwc[((uint32_t)ih * W + (uint32_t)iw) * C + c];
                        }
                        row[idx++] = v;
                    }
                }
            }
        }
    }
}

// ---------------------------------------------------------------------------------
// Referencia so em software para accel_matmul_i8: mesma semantica (C = A @ W com
// correcao de zero-point, -zp_a * soma(W[:,n])) e mesmo layout, sem o acelerador.
// A soma inteira e associativa, entao o resultado e bit a bit igual ao do caminho
// por tiles 8x8. Ordem m, k, n: cada linha de W e lida em sequencia e acumulada
// num vetor local, a forma direta de escrever esse laco na CPU.
// ---------------------------------------------------------------------------------
#define SW_MATMUL_MAX_N 128u // maior N do modelo (dense1)

static void sw_matmul_i8(const int8_t *A, uint32_t M, uint32_t K,
                         const int8_t *W, uint32_t N,
                         int32_t zp_a,
                         int32_t *C) {
    int32_t acc[SW_MATMUL_MAX_N];
    int32_t wcolsum[SW_MATMUL_MAX_N];
    if (N > SW_MATMUL_MAX_N) {
        neorv32_uart0_printf("[sw_matmul] N=%u excede %u\n", N, SW_MATMUL_MAX_N);
        return;
    }

    for (uint32_t n = 0; n < N; n++) wcolsum[n] = 0;
    for (uint32_t k = 0; k < K; k++) {
        for (uint32_t n = 0; n < N; n++) wcolsum[n] += (int32_t)W[k * N + n];
    }

    for (uint32_t m = 0; m < M; m++) {
        for (uint32_t n = 0; n < N; n++) acc[n] = 0;
        for (uint32_t k = 0; k < K; k++) {
            int32_t a = (int32_t)A[m * K + k];
            const int8_t *wrow = W + k * N;
            for (uint32_t n = 0; n < N; n++) acc[n] += a * (int32_t)wrow[n];
        }
        for (uint32_t n = 0; n < N; n++) C[m * N + n] = acc[n] - zp_a * wcolsum[n];
    }
}

static void matmul_i8(int use_accel, const int8_t *A, uint32_t M, uint32_t K,
                      const int8_t *W, uint32_t N, int32_t zp_a, int32_t *C) {
    if (use_accel) accel_matmul_i8(A, M, K, W, N, zp_a, C);
    else           sw_matmul_i8(A, M, K, W, N, zp_a, C);
}

static inline int8_t requantize(int32_t acc_plus_bias, float multiplier,
                                 int32_t out_zp, int relu) {
    float v = (float)acc_plus_bias * multiplier;
    int32_t q = (int32_t)(v + (v >= 0.0f ? 0.5f : -0.5f)) + out_zp;
    int32_t floor_v = relu ? out_zp : -128;
    if (q < floor_v) q = floor_v;
    if (q > 127) q = 127;
    return (int8_t)q;
}

// Camada conv2d 3x3 "same"/stride1 via im2col + acelerador. input_hwc/output_hwc
// tem layout (H*W) x C (canais contiguos por pixel), compativel diretamente com a
// proxima camada (conv ou flatten) sem necessidade de transposicao.
static void conv2d_layer(int use_accel, const model_layer_t *L, const int8_t *input_hwc, int8_t *output_hwc) {
    int8_t *im2col = (int8_t*)SDRAM_ADDR(SDRAM_OFF_IM2COL);
    build_im2col(input_hwc, L->in_h, L->in_w, L->in_c, (int8_t)L->in_zero_point, im2col);

    uint32_t M = L->in_h * L->in_w; // "same" padding + stride 1 -> OUT_H*OUT_W == IN_H*IN_W
    const int8_t  *Wt   = (const int8_t*)(SDRAM_BASE + SDRAM_OFF_WEIGHTS + L->w_offset);
    const int32_t *bias = (const int32_t*)(SDRAM_BASE + SDRAM_OFF_WEIGHTS + L->b_offset);
    int32_t *acc = (int32_t*)SDRAM_ADDR(SDRAM_OFF_ACC);

    matmul_i8(use_accel, im2col, M, L->k, Wt, L->n, L->in_zero_point, acc);

    float mult = L->in_scale * L->w_scale / L->out_scale;
    for (uint32_t m = 0; m < M; m++) {
        for (uint32_t n = 0; n < L->n; n++) {
            int32_t v = acc[m * L->n + n] + bias[n];
            output_hwc[m * L->n + n] = requantize(v, mult, L->out_zero_point, L->relu);
        }
    }
}

// Camada fully-connected via acelerador (M=1: um unico vetor de entrada).
static void dense_layer(int use_accel, const model_layer_t *L, const int8_t *input_vec, int8_t *output_vec) {
    const int8_t  *Wt   = (const int8_t*)(SDRAM_BASE + SDRAM_OFF_WEIGHTS + L->w_offset);
    const int32_t *bias = (const int32_t*)(SDRAM_BASE + SDRAM_OFF_WEIGHTS + L->b_offset);
    int32_t *acc = (int32_t*)SDRAM_ADDR(SDRAM_OFF_ACC);

    matmul_i8(use_accel, input_vec, 1, L->k, Wt, L->n, L->in_zero_point, acc);

    float mult = L->in_scale * L->w_scale / L->out_scale;
    for (uint32_t n = 0; n < L->n; n++) {
        int32_t v = acc[n] + bias[n];
        output_vec[n] = requantize(v, mult, L->out_zero_point, L->relu);
    }
}

// Max-pooling 2x2/stride2. TFLite mantem a mesma escala/zero-point do tensor de
// entrada (confirmado em model_meta.h: pool nao tem multiplicador proprio), entao
// basta comparar os codigos INT8 diretamente (max e monotona em relacao ao valor
// real representado).
static void maxpool2x2(const int8_t *in_hwc, uint32_t H, uint32_t W, uint32_t C,
                        int8_t *out_hwc) {
    uint32_t oh_n = H / 2, ow_n = W / 2;
    for (uint32_t oh = 0; oh < oh_n; oh++) {
        for (uint32_t ow = 0; ow < ow_n; ow++) {
            for (uint32_t c = 0; c < C; c++) {
                int8_t a = in_hwc[((2*oh+0) * W + (2*ow+0)) * C + c];
                int8_t b = in_hwc[((2*oh+0) * W + (2*ow+1)) * C + c];
                int8_t d = in_hwc[((2*oh+1) * W + (2*ow+0)) * C + c];
                int8_t e = in_hwc[((2*oh+1) * W + (2*ow+1)) * C + c];
                int8_t m1 = (a > b) ? a : b;
                int8_t m2 = (d > e) ? d : e;
                out_hwc[(oh * ow_n + ow) * C + c] = (m1 > m2) ? m1 : m2;
            }
        }
    }
}

static int argmax_i8(const int8_t *v, int n) {
    int best = 0;
    for (int i = 1; i < n; i++) {
        if (v[i] > v[best]) best = i;
    }
    return best;
}

// Fecha a medicao de uma etapa: imprime e acumula no total. O formato da linha
// "[bench] <etapa> : N ciclos" e lido pelo app desktop (board.py, RE_BENCH); o
// caminho so em software usa "[bench-sw]", que esse parser ignora.
static void bench_report(const char *tag, const char *stage, uint64_t t0, uint32_t *total) {
    uint32_t dt = (uint32_t)(neorv32_cpu_get_cycle() - t0);
    *total += dt;
    neorv32_uart0_printf("%s %s: %u ciclos\n", tag, stage, dt);
}

int run_inference(int use_accel, int8_t *logits, uint32_t *total_cycles) {
    int8_t *buf_a = (int8_t*)SDRAM_ADDR(SDRAM_OFF_BUF_A);
    int8_t *buf_b = (int8_t*)SDRAM_ADDR(SDRAM_OFF_BUF_B);
    const int8_t *input = (const int8_t*)SDRAM_ADDR(SDRAM_OFF_INPUT);
    const char *tag = use_accel ? "[bench]" : "[bench-sw]";

    uint64_t t0;
    *total_cycles = 0;

    t0 = neorv32_cpu_get_cycle();
    lcd_goto(1, 0); lcd_puts("camada: conv1  ");
    conv2d_layer(use_accel, &MODEL_LAYERS[LAYER_CONV1], input, buf_a); // -> 28x28x32
    bench_report(tag, "conv1  ", t0, total_cycles);

    t0 = neorv32_cpu_get_cycle();
    lcd_goto(1, 0); lcd_puts("camada: pool1  ");
    maxpool2x2(buf_a, 28, 28, 32, buf_b); // -> 14x14x32
    bench_report(tag, "pool1  ", t0, total_cycles);

    t0 = neorv32_cpu_get_cycle();
    lcd_goto(1, 0); lcd_puts("camada: conv2  ");
    conv2d_layer(use_accel, &MODEL_LAYERS[LAYER_CONV2], buf_b, buf_a); // -> 14x14x64
    bench_report(tag, "conv2  ", t0, total_cycles);

    t0 = neorv32_cpu_get_cycle();
    lcd_goto(1, 0); lcd_puts("camada: pool2  ");
    maxpool2x2(buf_a, 14, 14, 64, buf_b); // -> 7x7x64 (=3136, ja "achatado" em HWC)
    bench_report(tag, "pool2  ", t0, total_cycles);

    t0 = neorv32_cpu_get_cycle();
    lcd_goto(1, 0); lcd_puts("camada: dense1 ");
    dense_layer(use_accel, &MODEL_LAYERS[LAYER_DENSE1], buf_b, buf_a); // -> 128
    bench_report(tag, "dense1 ", t0, total_cycles);

    t0 = neorv32_cpu_get_cycle();
    lcd_goto(1, 0); lcd_puts("camada: dense2 ");
    dense_layer(use_accel, &MODEL_LAYERS[LAYER_DENSE2], buf_a, buf_b); // -> 10 (logits)
    bench_report(tag, "dense2 ", t0, total_cycles);

    // Copia os logits da SDRAM para a pilha ANTES de imprimir. Imprimir lendo
    // direto da SDRAM mistura duas coisas num mesmo laco (acesso a SDRAM e
    // UART): se travar, nao da para saber qual foi. Com a copia, o laco de
    // impressao nao toca a SDRAM.
    for (int i = 0; i < OUTPUT_CLASSES; i++) logits[i] = buf_b[i];
    neorv32_uart0_printf("[logits copiados da SDRAM ok]\n%s ", use_accel ? "[logits]" : "[logits-sw]");
    for (int i = 0; i < OUTPUT_CLASSES; i++) {
        neorv32_uart0_printf("%d ", logits[i]);
    }
    neorv32_uart0_printf("\n[faults ate aqui: %u]\n", (unsigned)sdram_get_fault_count());
    neorv32_uart0_printf("[faults desistidos: %u]\n", (unsigned)sdram_get_fault_giveups());

    return argmax_i8(logits, OUTPUT_CLASSES);
}

// ---------------------------------------------------------------------------------
// Benchmark SW (CPU) vs HW (acelerador) para um unico tile 8x8x8 -- Metodologia
// 3.8, caso de teste 5.
// ---------------------------------------------------------------------------------
static void sw_matmul8x8x8(const int8_t A[64], const int8_t W[64], int32_t C[64]) {
    for (int m = 0; m < 8; m++) {
        for (int n = 0; n < 8; n++) {
            int32_t acc = 0;
            for (int k = 0; k < 8; k++) {
                acc += (int32_t)A[m*8+k] * (int32_t)W[k*8+n];
            }
            C[m*8+n] = acc;
        }
    }
}

void bench_sw_vs_hw(void) {
    int8_t A[64], W[64];
    int32_t C_sw[64], C_hw[64];
    for (int i = 0; i < 64; i++) {
        A[i] = (int8_t)(i - 32);
        W[i] = (int8_t)((i * 3) % 17 - 8);
    }

    uint64_t t0 = neorv32_cpu_get_cycle();
    sw_matmul8x8x8(A, W, C_sw);
    uint64_t t1 = neorv32_cpu_get_cycle();
    uint32_t cyc_sw = (uint32_t)(t1 - t0);

    t0 = neorv32_cpu_get_cycle();
    accel_matmul_i8(A, 8, 8, W, 8, 0, C_hw);
    t1 = neorv32_cpu_get_cycle();
    uint32_t cyc_hw = (uint32_t)(t1 - t0);

    int mismatches = 0;
    for (int i = 0; i < 64; i++) {
        if (C_sw[i] != C_hw[i]) mismatches++;
    }

    neorv32_uart0_printf("\n=== Benchmark SW vs HW (matmul 8x8x8 INT8) ===\n");
    neorv32_uart0_printf("SW (CPU):        %u ciclos\n", cyc_sw);
    neorv32_uart0_printf("HW (acelerador): %u ciclos\n", cyc_hw);
    if (mismatches == 0) {
        neorv32_uart0_printf("Resultados identicos (OK)\n");
    } else {
        neorv32_uart0_printf("ATENCAO: %d elementos divergentes entre SW e HW\n", mismatches);

        // Saber QUE diverge nao basta; e preciso ver COMO. Hipoteses baratas:
        int all_zero = 1, is_transp = 1, is_neg = 1;
        for (int i = 0; i < 64; i++) if (C_hw[i] != 0) { all_zero = 0; break; }
        for (int m = 0; m < 8; m++)
            for (int n = 0; n < 8; n++) {
                if (C_hw[m*8+n] != C_sw[n*8+m]) is_transp = 0;
                if (C_hw[m*8+n] != -C_sw[m*8+n]) is_neg = 0;
            }
        neorv32_uart0_printf("  HW todo zero? %s | HW == transposta(SW)? %s | HW == -SW? %s\n",
                             all_zero ? "SIM" : "nao", is_transp ? "SIM" : "nao", is_neg ? "SIM" : "nao");

        neorv32_uart0_printf("  linha 0  SW:");
        for (int n = 0; n < 8; n++) neorv32_uart0_printf(" %i", (int)C_sw[n]);
        neorv32_uart0_printf("\n  linha 0  HW:");
        for (int n = 0; n < 8; n++) neorv32_uart0_printf(" %i", (int)C_hw[n]);
        neorv32_uart0_printf("\n  coluna 0 SW:");
        for (int m = 0; m < 8; m++) neorv32_uart0_printf(" %i", (int)C_sw[m*8]);
        neorv32_uart0_printf("\n  coluna 0 HW:");
        for (int m = 0; m < 8; m++) neorv32_uart0_printf(" %i", (int)C_hw[m*8]);
        neorv32_uart0_printf("\n");
    }
    // Speedup em 32 bits. A versao anterior usava (uint64_t) no numerador, o que
    // forcava divisao de 64 bits (__udivdi3) e travava o firmware no meio da
    // impressao desta linha. O resto cabe folgado em 32 bits: o maximo de
    // (cyc_sw % cyc_hw) * 100 fica na casa de 1,9 milhao para este benchmark.
    uint32_t sp_int  = cyc_sw / cyc_hw;
    uint32_t sp_frac = ((cyc_sw % cyc_hw) * 100u) / cyc_hw;
    // o printf minimo do NEORV32 nao suporta largura (%02u): zero a esquerda na mao
    neorv32_uart0_printf("Speedup HW/SW: %u.%s%u x\n", sp_int, (sp_frac < 10) ? "0" : "", sp_frac);
}
