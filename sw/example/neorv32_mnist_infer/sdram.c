// ================================================================================ //
// NEORV32 MNIST Inference (Fase 3/4 do TCC) - Acesso a SDRAM e carga via UART      //
// ================================================================================ //
#include "sdram.h"
#include <neorv32.h>

#define BLOB_CHUNK_SIZE  64
#define BLOB_BYTE_TIMEOUT_MS 200

// Le um byte com timeout limitado (-1 se nada chegar a tempo). Alguns
// adaptadores USB-serial baratos (ex.: CH340) derrubam bytes esporadicamente
// em transferencias longas -- sem timeout, um byte perdido trava o firmware
// para sempre esperando por ele, sem chance do host perceber e reenviar.
static int uart0_getc_timeout(uint32_t timeout_ms) {
    uint32_t clk = neorv32_sysinfo_get_clk();
    for (uint32_t waited = 0; waited < timeout_ms; waited++) {
        if (neorv32_uart0_char_received()) {
            return (uint8_t)neorv32_uart0_char_received_get();
        }
        neorv32_aux_delay_ms(clk, 1);
    }
    return -1;
}

// Descarta qualquer byte que ainda chegue por ~50ms. Usado apos uma falha de
// pedaco: os bytes "atrasados" do pedaco que acabou de falhar podem ainda
// estar a caminho, e se nao forem descartados aqui, se misturam com o
// reenvio do host e dessincronizam o protocolo permanentemente (toda
// tentativa seguinte falharia tambem, nao so essa).
static void uart0_drain(void) {
    uint32_t clk = neorv32_sysinfo_get_clk();
    uint32_t idle_ms = 0;
    while (idle_ms < 50) {
        if (neorv32_uart0_char_received()) {
            (void)neorv32_uart0_char_received_get();
            idle_ms = 0;
        } else {
            neorv32_aux_delay_ms(clk, 1);
            idle_ms++;
        }
    }
}

// Recebe o blob em pedacos pequenos, cada um confirmado individualmente
// ('K'=ok, avanca / 'N'=falhou, host deve reenviar o mesmo pedaco). Ver
// tools/send_weights.py para o lado host do protocolo.
uint32_t sdram_uart_recv_blob(uint32_t sdram_offset) {
    uint32_t len = 0;
    for (int i = 0; i < 4; i++) {
        uint32_t b = (uint8_t)neorv32_uart0_getc();
        len |= (b << (8 * i));
    }

    volatile uint8_t *dst = (volatile uint8_t*)(SDRAM_BASE + sdram_offset);
    uint32_t received = 0;
    while (received < len) {
        uint32_t want = len - received;
        if (want > BLOB_CHUNK_SIZE) {
            want = BLOB_CHUNK_SIZE;
        }
        neorv32_uart0_putc('S'); // starting this chunk

        uint8_t buf[BLOB_CHUNK_SIZE];
        int ok = 1;
        for (uint32_t i = 0; i < want; i++) {
            int c = uart0_getc_timeout(BLOB_BYTE_TIMEOUT_MS);
            if (c < 0) {
                neorv32_uart0_putc('T'); // this byte timed out
                ok = 0;
                break;
            }
            neorv32_uart0_putc('.'); // this byte arrived ok
            buf[i] = (uint8_t)c;
        }

        if (ok) {
            for (uint32_t i = 0; i < want; i++) {
                dst[received + i] = buf[i];
            }
            received += want;
            neorv32_uart0_putc('K');
        } else {
            uart0_drain(); // descarta bytes atrasados do pedaco que falhou
            neorv32_uart0_putc('N'); // host reenvia este mesmo pedaco
        }
    }

    // ack: devolve o tamanho recebido (4 bytes little-endian) para o host confirmar
    for (int i = 0; i < 4; i++) {
        neorv32_uart0_putc((char)((len >> (8 * i)) & 0xFF));
    }

    return len;
}

void sdram_uart_handshake_loop(void) {
    while (1) {
        // re-send 'R' periodically instead of blocking on it once: a host
        // script that connects a moment late would otherwise miss the only
        // 'R' ever sent and hang forever waiting for a command
        // Poll every 1ms (not a single 300ms sleep): a long blind window
        // between checks lets the host's very next bytes (cmd+len+first
        // chunk) overrun the small RX FIFO before we ever look at it.
        neorv32_uart0_putc('R'); // ready
        uint32_t waited_ms = 0;
        while (!neorv32_uart0_char_received()) {
            neorv32_aux_delay_ms(neorv32_sysinfo_get_clk(), 1);
            if (++waited_ms >= 300) {
                neorv32_uart0_putc('R');
                waited_ms = 0;
            }
        }
        char cmd = neorv32_uart0_char_received_get();
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
