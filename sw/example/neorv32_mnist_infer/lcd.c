#include <neorv32.h>
#include "lcd.h"

#define LCD_DATA_SHIFT 8
#define LCD_RS_BIT     16
#define LCD_EN_BIT     17
#define LED_MASK       0x000000FFu  // gpio[7:0] pertence aos LEDs; nunca sobrescrever

// Espelho do estado de saida. neorv32_gpio_port_get() le os PINOS DE ENTRADA, nao
// o latch de saida, entao ler-modificar-escrever com ele perderia o valor atual.
static uint32_t gpio_shadow = 0;

static uint32_t cycles_per_us = 50; // corrigido em lcd_init() pelo clock real

static void delay_us(uint32_t us) {
    uint64_t t0 = neorv32_cpu_get_cycle();
    uint64_t n  = (uint64_t)us * cycles_per_us;
    while ((neorv32_cpu_get_cycle() - t0) < n) {
        // espera ativa: o HD44780 nao tem handshake, so tempos minimos
    }
}

static void gpio_apply(void) {
    neorv32_gpio_port_set(gpio_shadow);
}

// Coloca dado e RS nas linhas e pulsa EN. Tempos do HD44780: EN alto >= 450ns,
// ciclo completo >= 1us -- aqui com folga larga, o custo e irrelevante.
static void lcd_write(uint8_t data, int rs) {
    gpio_shadow = (gpio_shadow & LED_MASK)
                | ((uint32_t)data << LCD_DATA_SHIFT)
                | ((uint32_t)(rs ? 1u : 0u) << LCD_RS_BIT);
    gpio_apply();
    delay_us(1);

    gpio_shadow |= (1u << LCD_EN_BIT);
    gpio_apply();
    delay_us(2);

    gpio_shadow &= ~(1u << LCD_EN_BIT);
    gpio_apply();
    delay_us(50); // a maioria dos comandos precisa de ~37us
}

static void lcd_cmd(uint8_t c)  { lcd_write(c, 0); }
static void lcd_data(uint8_t d) { lcd_write(d, 1); }

void lcd_init(void) {
    uint32_t clk = neorv32_sysinfo_get_clk();
    cycles_per_us = clk / 1000000u;
    if (cycles_per_us == 0) cycles_per_us = 1;

    gpio_shadow &= LED_MASK;
    gpio_apply();

    delay_us(50000); // >= 15ms apos energizar, com margem

    // Function set repetido tres vezes: o controlador pode ter iniciado em modo
    // 4 bits, e essa sequencia o leva deterministicamente para 8 bits.
    lcd_cmd(0x30); delay_us(5000);
    lcd_cmd(0x30); delay_us(200);
    lcd_cmd(0x30); delay_us(200);

    lcd_cmd(0x38); // 8 bits, 2 linhas, fonte 5x8
    lcd_cmd(0x08); // display off
    lcd_cmd(0x01); delay_us(2000); // clear (precisa de ~1,52ms)
    lcd_cmd(0x06); // entrada: incrementa cursor, sem shift
    lcd_cmd(0x0C); // display on, cursor off, sem piscar
}

void lcd_clear(void) {
    lcd_cmd(0x01);
    delay_us(2000);
}

void lcd_goto(int row, int col) {
    uint8_t addr = (uint8_t)((row ? 0x40 : 0x00) + col);
    lcd_cmd((uint8_t)(0x80 | addr));
}

void lcd_puts(const char *s) {
    while (*s) lcd_data((uint8_t)*s++);
}

void lcd_puti(int32_t v) {
    char buf[12];
    int i = 0;
    if (v < 0) { lcd_data('-'); v = -v; }
    if (v == 0) { lcd_data('0'); return; }
    while (v > 0 && i < (int)sizeof(buf)) { buf[i++] = (char)('0' + (v % 10)); v /= 10; }
    while (i > 0) lcd_data((uint8_t)buf[--i]);
}
