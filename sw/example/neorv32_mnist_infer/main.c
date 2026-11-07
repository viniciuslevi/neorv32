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

// Baud da APLICACAO. Independente do baud do bootloader (19200, fixo em
// sw/bootloader/config.h e embutido no bitstream): o bootloader so transfere os
// ~16 KB do firmware, enquanto os 422 KB de pesos passam por aqui. O protocolo
// confirma a cada 64 bytes e o FIFO de RX tem 64 entradas, entao a vazao e
// autolimitada -- subir o baud nao arrisca estouro.
// Use: python tools/send_weights.py --baud 115200 ...
#define APP_UART_BAUD 115200
#include "model_meta.h"


// KEY[1] chega em gpio_i(0) ja invertido pelo top-level: '1' = pressionado.
// Espera um clique completo (pressionar e soltar), com anti-repique simples,
// para que o resultado permaneca no LCD ate o operador pedir a proxima imagem.
static void wait_key1(void) {
    uint32_t clk = neorv32_sysinfo_get_clk();
    while (neorv32_gpio_pin_get(0) != 0) { }   // se ja estiver premido, espera soltar
    while (neorv32_gpio_pin_get(0) == 0) { }   // espera pressionar
    neorv32_aux_delay_ms(clk, 20);
    while (neorv32_gpio_pin_get(0) != 0) { }   // espera soltar
    neorv32_aux_delay_ms(clk, 20);
}

// Comandos 'S' e 'C': repetem a inferencia da mesma imagem por outro caminho e
// comparam com a do acelerador com DMA. 'S' = so na CPU, mede o ganho sobre a
// rede inteira (o bench_sw_vs_hw mede um unico tile). 'C' = acelerador com a
// CPU movendo os dados (o caminho de antes do DMA), mede o ganho do DMA. Nos
// dois casos os logits tem de ser identicos.
static void compare_inference(infer_mode_t mode, const int8_t *logits_hw, uint32_t cyc_hw) {
    int8_t logits_ref[OUTPUT_CLASSES];
    uint32_t cyc_ref;
    const char *nome = (mode == INFER_SW) ? "sw" : "cpu";

    neorv32_uart0_printf("\nExecutando inferencia %s (referencia)...\n",
                         (mode == INFER_SW) ? "so em software" : "com a CPU movendo os dados");
    lcd_clear();
    lcd_goto(0, 0); lcd_puts((mode == INFER_SW) ? "Inferindo (SW)" : "Inferindo (CPU)");
    int classe_ref = run_inference(mode, logits_ref, &cyc_ref);

    int iguais = 1;
    for (int i = 0; i < OUTPUT_CLASSES; i++) {
        if (logits_ref[i] != logits_hw[i]) iguais = 0;
    }
    neorv32_uart0_printf("[total-%s] %u ciclos\n", nome, cyc_ref);
    neorv32_uart0_printf("[%s-vs-hw] classe %s: %d | logits identicos: %s\n",
                         nome, nome, classe_ref, iguais ? "SIM" : "NAO");
    // Divisao so em 32 bits (ver bench_sw_vs_hw: __udivdi3 travava o firmware).
    // (cyc_ref % cyc_hw) * 100 estouraria 32 bits com totais na casa de 10^8,
    // por isso a fracao divide pelo centesimo de cyc_hw.
    uint32_t sp_int  = cyc_ref / cyc_hw;
    uint32_t sp_frac = (cyc_hw >= 100u) ? (cyc_ref % cyc_hw) / (cyc_hw / 100u) : 0u;
    if (sp_frac > 99u) sp_frac = 99u;
    neorv32_uart0_printf("[speedup] inferencia completa HW/%s: %u.%s%u x\n",
                         (mode == INFER_SW) ? "SW" : "CPU", sp_int, (sp_frac < 10) ? "0" : "", sp_frac);
}

#ifdef SIM_PRELOADED
// ---------------------------------------------------------------------------------
// Simulacao do SoC (sim/run_infer_sim.sh, make SIM=1): o modelo da SDRAM ja
// carregou weights.bin e a imagem no tempo 0, no lugar do upload pela UART.
// Roda UMA inferencia no modo SIM_INFER_MODE e escreve o fim em LEDG (0xA5 =
// terminou, 0xEE = erro), que e o que a testbench espera. Sem diagnostico da
// SDRAM, benchmark nem LCD: cada milissegundo da placa custa ~4 s de simulacao.
// ---------------------------------------------------------------------------------
#ifndef SIM_INFER_MODE
#define SIM_INFER_MODE INFER_ACCEL_DMA
#endif

static int sim_main(void) {
    neorv32_uart0_printf("\n=== inferencia na simulacao: tile %ux%u, modo %u ===\n",
                         ACCEL_TILE, ACCEL_TILE, (unsigned)SIM_INFER_MODE);
    uint32_t info = accel_check();
    if (info != 0 || accel_dma_init() != 0) {
        neorv32_uart0_printf("[erro] INFO = 0x%x ou DMA ausente\n", (unsigned)info);
        neorv32_gpio_port_set(0xEE);
        return 1;
    }
    int8_t logits[OUTPUT_CLASSES];
    uint32_t cyc;
    int classe = run_inference((infer_mode_t)SIM_INFER_MODE, logits, &cyc);
    neorv32_uart0_printf("[total] %u ciclos\n", cyc);
    neorv32_uart0_printf(">>> Classe prevista: %d <<<\n", classe);
    neorv32_gpio_port_set(0xA5);
    return 0;
}
#endif

int main(void) {
    neorv32_uart0_setup(APP_UART_BAUD, 0);
    neorv32_rte_setup(); // instala handlers de debug para excecoes/interrupcoes nao tratadas
    sdram_install_fault_retry_handler(); // retry automatico em access fault na SDRAM
#ifdef SIM_PRELOADED
    return sim_main();
#endif
    neorv32_uart0_printf("\n=== NEORV32 + Acelerador Sistolico - Inferencia MNIST (TCC Fase 3/4) ===\n");
    neorv32_uart0_printf("Modelo: %u camadas, %u bytes de pesos\n", (unsigned)MODEL_NUM_LAYERS, (unsigned)MODEL_WEIGHTS_BYTES);
    neorv32_uart0_printf("SDRAM base: 0x%x\n", (unsigned)SDRAM_BASE);

    lcd_init();
    lcd_goto(0, 0); lcd_puts("NEORV32 + MNIST");
    lcd_goto(1, 0); lcd_puts("testando SDRAM");

    sdram_diag_run(); // bateria completa: mapa de erros por bit, estabilidade, faults

    // O firmware e compilado para um tamanho de array (ACCEL_TILE); um bitstream
    // de outro tamanho daria resultados errados sem aviso.
    uint32_t info = accel_check();
    if (info != 0) {
        neorv32_uart0_printf("[erro] acelerador com INFO = 0x%x, firmware compilado para %ux%u\n",
                             (unsigned)info, ACCEL_TILE, ACCEL_TILE);
        lcd_clear();
        lcd_goto(0, 0); lcd_puts("ERRO: tamanho");
        lcd_goto(1, 0); lcd_puts("do acelerador");
        while (1) { }
    }
    if (accel_dma_init() != 0) {
        neorv32_uart0_printf("[erro] DMA ausente no bitstream (IO_DMA_EN)\n");
        lcd_clear();
        lcd_goto(0, 0); lcd_puts("ERRO: sem DMA");
        while (1) { }
    }
    neorv32_uart0_printf("Acelerador %ux%u, DMA ligado\n", ACCEL_TILE, ACCEL_TILE);

    bench_sw_vs_hw(); // uma vez, antes do laco: nao depende de pesos nem de imagem

    // Apos cada inferencia volta ao handshake, para receber a proxima imagem sem
    // reenviar os 422 KB de pesos nem refazer o upload do firmware. Envie os pesos
    // uma vez; depois basta a imagem + go por imagem.
    while (1) {
        lcd_clear();
        lcd_goto(0, 0); lcd_puts("Aguardando");
        lcd_goto(1, 0); lcd_puts("imagem via UART");
        neorv32_uart0_printf("\nAguardando handshake UART (host: tools/send_weights.py)...\n");
        char cmd = sdram_uart_handshake_loop();

        lcd_clear();
        lcd_goto(0, 0); lcd_puts("Inferindo...");

        neorv32_uart0_printf("\nExecutando inferencia...\n");
        int8_t logits[OUTPUT_CLASSES];
        uint32_t cyc_hw;
        int classe = run_inference(INFER_ACCEL_DMA, logits, &cyc_hw);
        neorv32_uart0_printf("[total] %u ciclos\n", cyc_hw);
        neorv32_uart0_printf("\n>>> Classe prevista: %d <<<\n", classe);

        if (cmd == 'S') {
            compare_inference(INFER_SW, logits, cyc_hw);
        } else if (cmd == 'C') {
            compare_inference(INFER_ACCEL_CPU, logits, cyc_hw);
        }

        lcd_clear();
        lcd_goto(0, 0); lcd_puts("Classe: ");
        lcd_puti(classe);

        // 'H', 'S' e 'C' vem de coleta automatica pelo host: volta direto ao
        // handshake. 'G' (uso interativo) segura o resultado no display ate o
        // clique: sem isso o laco voltava ao handshake e limpava o LCD antes
        // de dar tempo de ler.
        if (cmd == 'G') {
            lcd_goto(1, 0); lcd_puts("KEY1 = proxima");
            neorv32_uart0_printf("(pressione KEY1 na placa para a proxima imagem)\n");
            wait_key1();
        } else {
            neorv32_uart0_printf("[fim]\n");
        }
    }

    return 0;
}
