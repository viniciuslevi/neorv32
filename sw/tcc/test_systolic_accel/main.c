// ================================================================================ //
// NEORV32 Systolic Array Accelerator Test (Wishbone/XBUS)                          //
// -------------------------------------------------------------------------------- //
// Tests the 8x8 systolic array accelerator connected via external Wishbone bus.    //
// Base address is configurable via ACCEL_BASE.                                     //
//                                                                                  //
// Address map (relative to base):                                                  //
//   0x000  CTRL   [2] irq_clear, [1] clear, [0] start                             //
//   0x004  STATUS [2] irq_pending, [1] done, [0] busy                             //
//   0x008  CONFIG (reserved)                                                       //
//   0x100  WEIGHT memory (16 words, 4xINT8 packed)                                //
//   0x500  ACT memory (16 words, 4xINT8 packed)                                   //
//   0x900  RESULT memory (64 words, INT32, read-only)                             //
// ================================================================================ //

#include <neorv32.h>
#include <stdint.h>

#define ACCEL_BASE 0x90000000

#define ACCEL_CTRL   (*(volatile uint32_t*)(ACCEL_BASE + 0x000))
#define ACCEL_STATUS (*(volatile uint32_t*)(ACCEL_BASE + 0x004))
#define ACCEL_CONFIG (*(volatile uint32_t*)(ACCEL_BASE + 0x008))

#define ACCEL_WEIGHT(addr) (*(volatile uint32_t*)(ACCEL_BASE + 0x100 + ((addr)<<2)))
#define ACCEL_ACT(addr)    (*(volatile uint32_t*)(ACCEL_BASE + 0x500 + ((addr)<<2)))
#define ACCEL_RESULT(addr) (*(volatile uint32_t*)(ACCEL_BASE + 0x900 + ((addr)<<2)))

static inline uint32_t pack4i8(int8_t b0, int8_t b1, int8_t b2, int8_t b3) {
    return ((uint32_t)(uint8_t)b0 << 0)  |
           ((uint32_t)(uint8_t)b1 << 8)  |
           ((uint32_t)(uint8_t)b2 << 16) |
           ((uint32_t)(uint8_t)b3 << 24);
}

static int errors = 0;

static void check(const char *name, uint32_t actual, uint32_t expected) {
    if (actual != expected) {
        neorv32_uart0_printf("[FAIL] %s: expected 0x%x, got 0x%x\n", name, expected, actual);
        errors++;
    } else {
        neorv32_uart0_printf("[PASS] %s\n", name);
    }
}

static void accel_clear(void) {
    ACCEL_CTRL = 0x00000002;
    while (ACCEL_STATUS & 0x01);
}

static void accel_wait_done(void) {
    while (!(ACCEL_STATUS & 0x02));
}

int main(void) {
    neorv32_uart0_setup(19200, 0);
    neorv32_uart0_printf("\n=== Systolic Array Accelerator Test ===\n\n");

    neorv32_uart0_printf("Test 1: Register R/W...\n");
    ACCEL_CTRL = 0x00000005;
    check("CTRL wr/rd", ACCEL_CTRL, 0x00000005);
    accel_clear();

    // RESULT = ACT @ WEIGHT (ver cabecalho de tcc_systolic_wb_accelerator.vhd).
    // identity(8x8) @ ones(8x8) = ones(8x8) -> cada RESULT[m][n] deve valer 1.
    neorv32_uart0_printf("Test 2: Identity x Ones (expect result=1 per entry)...\n");

    int8_t identity[64];
    for (int k = 0; k < 8; k++) {
        for (int n = 0; n < 8; n++) {
            identity[k*8+n] = (k == n) ? 1 : 0;
        }
    }
    for (int w = 0; w < 16; w++) {
        ACCEL_WEIGHT(w) = pack4i8(identity[w*4+0], identity[w*4+1], identity[w*4+2], identity[w*4+3]);
    }

    for (int i = 0; i < 16; i++) {
        ACCEL_ACT(i) = pack4i8(1, 1, 1, 1);
    }

    ACCEL_CTRL = 0x00000001;
    accel_wait_done();

    for (int i = 0; i < 64; i++) {
        uint32_t r = ACCEL_RESULT(i);
        neorv32_uart0_printf("  RESULT[%d] = %d\n", i, (int32_t)r);
    }

    uint32_t r0 = ACCEL_RESULT(0);
    check("RESULT[0] == 1", r0, 1);

    neorv32_uart0_printf("Test 3: IRQ...\n");
    check("IRQ pending", (ACCEL_STATUS >> 2) & 1, 1);
    ACCEL_CTRL = 0x00000004;
    check("IRQ cleared", (ACCEL_STATUS >> 2) & 1, 0);

    neorv32_uart0_printf("\n=== Results: %d errors ===\n", errors);
    if (errors == 0) {
        neorv32_uart0_printf("ALL TESTS PASSED\n");
    } else {
        neorv32_uart0_printf("SOME TESTS FAILED\n");
    }

    return errors;
}
