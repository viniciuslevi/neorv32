// ================================================================================ //
// LCD 16x2 (HD44780) da DE2-115, acionado por bit-bang via GPIO                    //
// -------------------------------------------------------------------------------- //
// Mapa de bits do GPIO (ver tcc_de2115_mnist_top.vhd):                         //
//   gpio[7:0]    LEDs verdes (uso preexistente, preservado)                        //
//   gpio[15:8]   LCD_DATA[7:0]                                                     //
//   gpio[16]     LCD_RS   (0 = comando, 1 = dado)                                  //
//   gpio[17]     LCD_EN   (pulso de escrita)                                       //
// LCD_RW fica fixo em 0 (somente escrita) e LCD_ON/BLON fixos em 1 no top-level,   //
// entao o busy flag nao e lido: as esperas seguem os tempos do datasheet.          //
// ================================================================================ //
#ifndef LCD_H
#define LCD_H

#include <stdint.h>

// Sequencia de inicializacao do HD44780 em modo 8 bits. Chamar uma vez no boot.
void lcd_init(void);

// Limpa o display e volta o cursor para a origem.
void lcd_clear(void);

// Posiciona o cursor. row: 0 ou 1. col: 0..15.
void lcd_goto(int row, int col);

// Escreve uma string a partir da posicao atual do cursor.
void lcd_puts(const char *s);

// Escreve um inteiro com sinal a partir da posicao atual.
void lcd_puti(int32_t v);

#endif // LCD_H
