// ================================================================================ //
// NEORV32 MNIST Inference (Fase 3/4 do TCC) - Acesso a SDRAM e carga via UART      //
// ================================================================================ //
#include "sdram.h"
#include <neorv32.h>

uint32_t sdram_uart_recv_blob(uint32_t sdram_offset) {
    uint32_t len = 0;
    for (int i = 0; i < 4; i++) {
        uint32_t b = (uint8_t)neorv32_uart0_getc();
        len |= (b << (8 * i));
    }

    volatile uint8_t *dst = (volatile uint8_t*)(SDRAM_BASE + sdram_offset);
    for (uint32_t i = 0; i < len; i++) {
        dst[i] = (uint8_t)neorv32_uart0_getc();
    }

    // ack: devolve o tamanho recebido (4 bytes little-endian) para o host confirmar
    for (int i = 0; i < 4; i++) {
        neorv32_uart0_putc((char)((len >> (8 * i)) & 0xFF));
    }

    return len;
}

void sdram_uart_handshake_loop(void) {
    while (1) {
        neorv32_uart0_putc('R'); // ready
        char cmd = neorv32_uart0_getc();
        if (cmd == 'W') {
            uint32_t n = sdram_uart_recv_blob(SDRAM_OFF_WEIGHTS);
            neorv32_uart0_printf("\n[sdram] pesos recebidos: %u bytes\n", n);
        } else if (cmd == 'I') {
            uint32_t n = sdram_uart_recv_blob(SDRAM_OFF_INPUT);
            neorv32_uart0_printf("\n[sdram] imagem recebida: %u bytes\n", n);
        } else if (cmd == 'G') {
            return;
        }
    }
}
