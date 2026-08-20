// ================================================================================ //
// NEORV32 MNIST Inference (Fase 3/4 do TCC)                                        //
// -------------------------------------------------------------------------------- //
// Fluxo: recebe pesos (weights.bin) e uma imagem 28x28 INT8 via UART0, grava na    //
// SDRAM (Fase 3: "Validar carga de tile via UART"), roda a CNN completa via         //
// acelerador sistolico (Fase 4: "inference.c: camadas + tiles"), imprime a classe   //
// prevista e os tempos por camada, e finaliza com o benchmark SW vs HW.            //
// Host companion: tools/send_weights.py                                            //
// ================================================================================ //
#include <neorv32.h>
#include "sdram.h"
#include "accel_driver.h"
#include "inference.h"
#include "model_meta.h"

int main(void) {
    neorv32_uart0_setup(19200, 0);
    neorv32_uart0_printf("\n=== NEORV32 + Acelerador Sistolico - Inferencia MNIST (TCC Fase 3/4) ===\n");
    neorv32_uart0_printf("Modelo: %u camadas, %u bytes de pesos\n", (unsigned)MODEL_NUM_LAYERS, (unsigned)MODEL_WEIGHTS_BYTES);
    neorv32_uart0_printf("SDRAM base: 0x%x\n", (unsigned)SDRAM_BASE);

    neorv32_uart0_printf("\n[dbg] SDRAM smoke test: escrevendo 16 bytes...\n");
    volatile uint8_t *sdram_test = (volatile uint8_t*)SDRAM_ADDR(0);
    for (int i = 0; i < 16; i++) {
        sdram_test[i] = (uint8_t)(0xA0 + i);
    }
    neorv32_uart0_printf("[dbg] SDRAM smoke test: lendo de volta...\n");
    int sdram_ok = 1;
    for (int i = 0; i < 16; i++) {
        uint8_t v = sdram_test[i];
        if (v != (uint8_t)(0xA0 + i)) {
            neorv32_uart0_printf("[dbg] MISMATCH em %d: esperado 0x%x, lido 0x%x\n", i, 0xA0 + i, v);
            sdram_ok = 0;
        }
    }
    neorv32_uart0_printf("[dbg] SDRAM smoke test: %s\n", sdram_ok ? "PASS" : "FAIL");

    neorv32_uart0_printf("\nAguardando handshake UART (host: tools/send_weights.py)...\n");
    sdram_uart_handshake_loop();

    neorv32_uart0_printf("\nExecutando inferencia...\n");
    int classe = run_inference();
    neorv32_uart0_printf("\n>>> Classe prevista: %d <<<\n", classe);

    bench_sw_vs_hw();

    neorv32_uart0_printf("\n=== Fim ===\n");
    return 0;
}
