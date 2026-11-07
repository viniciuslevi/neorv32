// ================================================================================ //
// Teste do acelerador sistolico com DMA (Proposta A, "Proposta 16x16 + DMA")       //
// -------------------------------------------------------------------------------- //
// Faz o mesmo matmul INT8 por tres caminhos e confere contra uma referencia em     //
// software:                                                                        //
//   cpu    accel_matmul_i8: a CPU junta os bytes e escreve no acelerador           //
//   dma    accel_matmul_dma sem sobreposicao: DMA -> calculo -> leitura            //
//   dma+o  accel_matmul_dma com sobreposicao (pesos do proximo tile durante o     //
//          calculo, ativacoes do proximo durante a leitura de RESULT)              //
// e um matvec (M = 1, como as camadas dense) pelos mesmos caminhos.                //
//                                                                                  //
// Roda na placa (UART0 a 115200) ou na simulacao do SoC (make sim_image, ver       //
// sim/tcc/run_soc_sim.sh), que termina quando LEDG recebe 0xA5 (PASS) ou 0xEE (FAIL).  //
// Os dados ficam nos primeiros 64 KB da SDRAM: o modelo de simulacao so guarda 16  //
// linhas por banco (sim/tcc/tcc_sdram_model.vhd).                                  //
// ================================================================================ //
#include <neorv32.h>
#include <stdint.h>
#include "accel_driver.h"

#define BAUD_RATE   115200
#define SDRAM_BASE  0xA0000000u
#define SDRAM_LIMIT 0x00010000u // 64 KB: ver cabecalho

// Matmul de teste: dimensoes que nao sao multiplas de 8 nem de 16, para passar
// pelos tiles de borda
#define MM_M 30
#define MM_K 70
#define MM_N 20
#define MM_ZP (-7)
// Matvec de teste (dense): K multiplo de 8 mas nao de 16
#define MV_K 136
#define MV_N 20
#define MV_ZP 5

static int8_t  A_ref[MM_M * MM_K];
static int8_t  W_ref[MM_K * MM_N];
static int32_t C_ref[MM_M * MM_N];
static int8_t  a_ref[MV_K] __attribute__((aligned(4)));
static int8_t  Wv_ref[MV_K * MV_N];
static int32_t c_ref[MV_N];

static uint32_t sdram_next = 0;
static int failures = 0;

// ---------------------------------------------------------------------------------
// Contagem (e retry) de access faults, como sdram.c do firmware de inferencia
// ---------------------------------------------------------------------------------
static volatile uint32_t fault_count = 0;

static void access_fault_retry_handler(void) {
    fault_count++;
    uint32_t mepc = neorv32_cpu_csr_read(CSR_MEPC);
    uint32_t mtinst = neorv32_cpu_csr_read(CSR_MTINST);
    int compressed = ((mtinst & 3) != 3);
    neorv32_cpu_csr_write(CSR_MEPC, mepc - (compressed ? 2 : 4)); // repete a instrucao
}

// ---------------------------------------------------------------------------------
// Utilitarios
// ---------------------------------------------------------------------------------
// mtime conta ciclos de clock mesmo com a CPU dormindo no wfi; mcycle nao conta
// (cnt_event_cy = 0 em S_SLEEP), e mediria so o tempo acordado.
static inline uint32_t now(void) {
    return NEORV32_CLINT->MTIME.uint32[0];
}

static void *sdram_alloc(uint32_t bytes) {
    uint32_t off = sdram_next;
    sdram_next = (off + bytes + 63u) & ~63u;
    if (sdram_next > SDRAM_LIMIT) {
        neorv32_uart0_printf("[erro] SDRAM de teste esgotada (%u B)\n", sdram_next);
        neorv32_gpio_port_set(0xEE);
        while (1);
    }
    return (void*)(SDRAM_BASE + off);
}

static uint32_t lcg_state = 12345u;
static int8_t rnd_i8(void) {
    lcg_state = lcg_state * 1664525u + 1013904223u;
    return (int8_t)(lcg_state >> 24);
}

static void sw_matmul(const int8_t *A, uint32_t M, uint32_t K, const int8_t *W, uint32_t N,
                      int32_t zp, int32_t *C) {
    for (uint32_t m = 0; m < M; m++) {
        for (uint32_t n = 0; n < N; n++) {
            int32_t s = 0;
            for (uint32_t k = 0; k < K; k++) {
                s += ((int32_t)A[m * K + k] - zp) * (int32_t)W[k * N + n];
            }
            C[m * N + n] = s;
        }
    }
}

static void copy_to_sdram(void *dst, const void *src, uint32_t bytes) {
    const int8_t *s = (const int8_t*)src;
    int8_t *d = (int8_t*)dst;
    for (uint32_t i = 0; i < bytes; i++) d[i] = s[i];
}

static void check(const char *name, const int32_t *got, const int32_t *ref, uint32_t n,
                  uint32_t cycles) {
    uint32_t bad = 0;
    for (uint32_t i = 0; i < n; i++) {
        if (got[i] != ref[i]) {
            if (bad < 3) {
                neorv32_uart0_printf("  [%s] C[%u] = %d, esperado %d\n", name, i, got[i], ref[i]);
            }
            bad++;
        }
    }
    neorv32_uart0_printf("[%s] %u ciclos, %s (%u/%u diferentes)\n", name, cycles,
                         bad ? "FALHOU" : "ok", bad, n);
    if (bad) failures++;
}

// ---------------------------------------------------------------------------------
int main(void) {
    neorv32_rte_setup();
    neorv32_uart0_setup(BAUD_RATE, 0);
    neorv32_rte_handler_install(TRAP_CODE_L_ACCESS, access_fault_retry_handler);
    neorv32_rte_handler_install(TRAP_CODE_S_ACCESS, access_fault_retry_handler);
    neorv32_gpio_port_set(0x01);

    neorv32_uart0_printf("\n=== accel_dma_test: tile %ux%u ===\n", ACCEL_TILE, ACCEL_TILE);

    uint32_t info = accel_check();
    if (info != 0) {
        neorv32_uart0_printf("[erro] INFO do acelerador = 0x%x, firmware compilado para %u\n",
                             info, ACCEL_TILE);
        neorv32_gpio_port_set(0xEE);
        return 1;
    }
    if (accel_dma_init() != 0) {
        neorv32_uart0_printf("[erro] DMA ausente no bitstream (IO_DMA_EN)\n");
        neorv32_gpio_port_set(0xEE);
        return 1;
    }

    // Dados e referencia (DMEM), copias na SDRAM
    for (uint32_t i = 0; i < MM_M * MM_K; i++) A_ref[i] = rnd_i8();
    for (uint32_t i = 0; i < MM_K * MM_N; i++) W_ref[i] = rnd_i8();
    for (uint32_t i = 0; i < MV_K; i++)        a_ref[i] = rnd_i8();
    for (uint32_t i = 0; i < MV_K * MV_N; i++) Wv_ref[i] = rnd_i8();

    neorv32_gpio_port_set(0x02); // etapa: referencia em software
    uint32_t t0 = now();
    sw_matmul(A_ref, MM_M, MM_K, W_ref, MM_N, MM_ZP, C_ref);
    uint32_t cyc_sw = now() - t0;
    sw_matmul(a_ref, 1, MV_K, Wv_ref, MV_N, MV_ZP, c_ref);

    int8_t  *A  = sdram_alloc(MM_M * MM_K);
    int8_t  *W  = sdram_alloc(MM_K * MM_N);
    int8_t  *At = sdram_alloc(accel_apack_bytes(MM_M, MM_K));
    void    *Wp = sdram_alloc(accel_wpack_bytes(MM_K, MM_N));
    int32_t *C  = sdram_alloc(MM_M * MM_N * 4);
    int8_t  *a  = sdram_alloc(MV_K + ACCEL_TILE);
    int8_t  *Wv = sdram_alloc(MV_K * MV_N);
    void    *Wvp = sdram_alloc(accel_wpack_bytes(MV_K, MV_N));
    int32_t *c  = sdram_alloc(MV_N * 4);
    copy_to_sdram(A, A_ref, sizeof(A_ref));
    copy_to_sdram(W, W_ref, sizeof(W_ref));
    copy_to_sdram(a, a_ref, sizeof(a_ref));
    copy_to_sdram(Wv, Wv_ref, sizeof(Wv_ref));

    neorv32_uart0_printf("matmul %ux%ux%u (zp %d), referencia em software: %u ciclos\n",
                         MM_M, MM_K, MM_N, MM_ZP, cyc_sw);

    // --- matmul ---
    neorv32_gpio_port_set(0x03);
    t0 = now();
    accel_matmul_i8(A, MM_M, MM_K, W, MM_N, MM_ZP, C);
    check("mm cpu  ", C, C_ref, MM_M * MM_N, now() - t0);

    accel_wpack_t wp;
    neorv32_gpio_port_set(0x04);
    t0 = now();
    accel_wpack(W, MM_K, MM_N, Wp, &wp);
    accel_apack(A, MM_M, MM_K, At);
    neorv32_uart0_printf("[mm pack ] %u ciclos (uma vez por camada nos pesos)\n", now() - t0);

    for (uint32_t i = 0; i < MM_M * MM_N; i++) C[i] = 0x5A5A5A5A;
    accel_dma_set_overlap(0);
    neorv32_gpio_port_set(0x05);
    t0 = now();
    accel_matmul_dma(At, MM_M, &wp, MM_ZP, C);
    check("mm dma  ", C, C_ref, MM_M * MM_N, now() - t0);

    for (uint32_t i = 0; i < MM_M * MM_N; i++) C[i] = 0x5A5A5A5A;
    accel_dma_set_overlap(1);
    neorv32_gpio_port_set(0x06);
    t0 = now();
    accel_matmul_dma(At, MM_M, &wp, MM_ZP, C);
    check("mm dma+o", C, C_ref, MM_M * MM_N, now() - t0);

    // --- matvec (dense) ---
    neorv32_gpio_port_set(0x07);
    neorv32_uart0_printf("matvec 1x%ux%u (zp %d)\n", MV_K, MV_N, MV_ZP);
    t0 = now();
    accel_matmul_i8(a, 1, MV_K, Wv, MV_N, MV_ZP, c);
    check("mv cpu  ", c, c_ref, MV_N, now() - t0);

    accel_wpack_t wvp;
    accel_wpack(Wv, MV_K, MV_N, Wvp, &wvp);
    for (uint32_t i = 0; i < MV_N; i++) c[i] = 0x5A5A5A5A;
    accel_dma_set_overlap(0);
    t0 = now();
    accel_matvec_dma(a, &wvp, MV_ZP, c);
    check("mv dma  ", c, c_ref, MV_N, now() - t0);

    for (uint32_t i = 0; i < MV_N; i++) c[i] = 0x5A5A5A5A;
    accel_dma_set_overlap(1);
    t0 = now();
    accel_matvec_dma(a, &wvp, MV_ZP, c);
    check("mv dma+o", c, c_ref, MV_N, now() - t0);

    neorv32_uart0_printf("access faults da CPU: %u | erros do DMA: %u\n",
                         fault_count, accel_dma_errors());
    if (accel_dma_errors() != 0) failures++;

    if (failures == 0) {
        neorv32_uart0_printf("=== accel_dma_test: PASS ===\n");
        neorv32_gpio_port_set(0xA5);
    } else {
        neorv32_uart0_printf("=== accel_dma_test: FAIL (%d) ===\n", failures);
        neorv32_gpio_port_set(0xEE);
    }
    return 0;
}
