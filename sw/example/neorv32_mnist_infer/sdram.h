// ================================================================================ //
// NEORV32 MNIST Inference (Fase 3/4 do TCC) - Acesso a SDRAM e carga via UART      //
// -------------------------------------------------------------------------------- //
// A SDRAM (neorv32_sdram_controller.vhd) e mapeada em memoria no barramento XBUS   //
// do NEORV32 e pode ser acessada como memoria comum (ponteiros volatile). Este     //
// modulo apenas define o mapa de regioes (Metodologia 3.4, "Mapa SDRAM proposto")  //
// e o protocolo simples de carga via UART0 (Metodologia 3.4, "Carregamento         //
// inicial dos pesos: UART no boot").                                              //
// ================================================================================ //
#ifndef SDRAM_H
#define SDRAM_H

#include <stdint.h>

#define SDRAM_BASE            0xA0000000u
#define SDRAM_SIZE            (128u * 1024u * 1024u)

// Regioes (offsets relativos a SDRAM_BASE) -- ver README da Fase 3/4 para detalhes
#define SDRAM_OFF_WEIGHTS      0x00000000u  // conteudo de weights.bin (pesos + bias, INT8/INT32)
#define SDRAM_OFF_INPUT        0x00100000u  // imagem de entrada, 28x28 INT8 (784 B)
#define SDRAM_OFF_BUF_A        0x00110000u  // buffer de ativacoes (ping-pong A), 256 KB
#define SDRAM_OFF_BUF_B        0x00150000u  // buffer de ativacoes (ping-pong B), 256 KB
#define SDRAM_OFF_IM2COL       0x00200000u  // matriz im2col temporaria (camadas conv), 512 KB
#define SDRAM_OFF_ACC           0x00300000u  // acumulador INT32 do matmul (M x N), 512 KB

#define SDRAM_ADDR(off) ((volatile void*)(SDRAM_BASE + (off)))

// Recebe um blob via UART0 e grava em SDRAM a partir de sdram_offset.
// Protocolo (ver tools/send_weights.py):
//   host -> placa: 4 bytes little-endian com o tamanho N do blob
//   host -> placa: N bytes de payload
// Retorna N (numero de bytes recebidos e gravados).
uint32_t sdram_uart_recv_blob(uint32_t sdram_offset);

// Envia magic byte 'R' (ready) e aguarda um comando de 1 byte do host:
//   'W' -> recebe pesos (sdram_uart_recv_blob em SDRAM_OFF_WEIGHTS)
//   'I' -> recebe uma imagem de entrada (sdram_uart_recv_blob em SDRAM_OFF_INPUT)
//   'G' -> go: encerra o handshake e retorna
// Usado por main.c para o fluxo interativo de carga (Fase 3, "Validar carga de
// tile via UART").
void sdram_uart_handshake_loop(void);

#endif // SDRAM_H
