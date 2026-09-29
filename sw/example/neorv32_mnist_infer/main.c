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
#include "sdram_diag.h"
#include "lcd.h"
#include "model_meta.h"

int main(void) {
    neorv32_uart0_setup(19200, 0);
    neorv32_rte_setup(); // instala handlers de debug para excecoes/interrupcoes nao tratadas
    sdram_install_fault_retry_handler(); // retry automatico em access fault na SDRAM
    neorv32_uart0_printf("\n=== NEORV32 + Acelerador Sistolico - Inferencia MNIST (TCC Fase 3/4) ===\n");
    neorv32_uart0_printf("Modelo: %u camadas, %u bytes de pesos\n", (unsigned)MODEL_NUM_LAYERS, (unsigned)MODEL_WEIGHTS_BYTES);
    neorv32_uart0_printf("SDRAM base: 0x%x\n", (unsigned)SDRAM_BASE);

    lcd_init();
    lcd_goto(0, 0); lcd_puts("NEORV32 + MNIST");
    lcd_goto(1, 0); lcd_puts("testando SDRAM");

    sdram_diag_run(); // bateria completa: mapa de erros por bit, estabilidade, faults

    bench_sw_vs_hw(); // uma vez, antes do laco: nao depende de pesos nem de imagem

    // Apos cada inferencia volta ao handshake, para receber a proxima imagem sem
    // reenviar os 422 KB de pesos nem refazer o upload do firmware. Envie os pesos
    // uma vez; depois basta a imagem + go por imagem.
    while (1) {
        lcd_clear();
        lcd_goto(0, 0); lcd_puts("Aguardando");
        lcd_goto(1, 0); lcd_puts("imagem via UART");
        neorv32_uart0_printf("\nAguardando handshake UART (host: tools/send_weights.py)...\n");
        sdram_uart_handshake_loop();

        lcd_clear();
        lcd_goto(0, 0); lcd_puts("Inferindo...");

        neorv32_uart0_printf("\nExecutando inferencia...\n");
        int classe = run_inference();
        neorv32_uart0_printf("\n>>> Classe prevista: %d <<<\n", classe);

        lcd_clear();
        lcd_goto(0, 0); lcd_puts("Classe prevista:");
        lcd_goto(1, 6); lcd_puti(classe);
    }

    return 0;
}
