#include <neorv32.h>
#include "sdram.h"
#include "sdram_diag.h"

// Quantidade de palavras de 32 bits por passada. 256 palavras = 1 KB: estatistica
// suficiente sem estourar o tempo de UART a 19200 baud.
#define NWORDS 256

// Offsets escolhidos para cair em bancos/linhas diferentes e forcar ciclos
// ACTIVE/PRECHARGE reais entre eles (o controlador usa politica close-page).
static const uint32_t test_offsets[] = {
  0x00000000u, 0x00400000u, 0x00800010u, 0x01000000u
};
#define NOFFSETS (sizeof(test_offsets) / sizeof(test_offsets[0]))

// Contagem de erros por bit, acumulada em toda a bateria.
static uint32_t bit_err[32];
static uint32_t st0[32], st1[32]; // esperado0-leu1 / esperado1-leu0

// Imprime bit_err[] agrupado de 8 em 8, do bit 31 ao 0.
static void print_bit_map(void) {
  for (int hi = 31; hi >= 0; hi -= 8) {
    neorv32_uart0_printf("  bits %i..%i :", hi, hi - 7);
    for (int b = hi; b > hi - 8; b--) {
      neorv32_uart0_printf(" %u", (unsigned)bit_err[b]);
    }
    neorv32_uart0_printf("\n");
  }
}

// Escreve `pat` em NWORDS palavras a partir de `off`, le de volta e acumula os
// bits divergentes. Retorna o numero de palavras com pelo menos 1 bit errado.
// `use_addr` != 0 usa o proprio endereco como dado (detecta aliasing de endereco).
static uint32_t pass_pattern(uint32_t off, uint32_t pat, int use_addr) {
  volatile uint32_t *p = (volatile uint32_t*)SDRAM_ADDR(off);
  for (uint32_t i = 0; i < NWORDS; i++) {
    p[i] = use_addr ? (uint32_t)(uintptr_t)&p[i] : pat;
  }
  uint32_t bad = 0;
  for (uint32_t i = 0; i < NWORDS; i++) {
    uint32_t want = use_addr ? (uint32_t)(uintptr_t)&p[i] : pat;
    uint32_t got  = p[i];
    uint32_t diff = want ^ got;
    if (diff) {
      bad++;
      for (int b = 0; b < 32; b++) {
        if (diff & (1u << b)) bit_err[b]++;
      }
    }
  }
  return bad;
}

// Separa erro de ESCRITA de erro de LEITURA: grava uma palavra uma unica vez e
// le varias. Se as leituras divergem ENTRE SI, o caminho de leitura e instavel;
// se concordam mas diferem do gravado, o problema esta na escrita (ou e estavel).
static void stability_test(uint32_t off) {
  volatile uint32_t *p = (volatile uint32_t*)SDRAM_ADDR(off);
  const uint32_t pat = 0xA5A55A5Au;
  *p = pat;
  uint32_t first = *p, unstable = 0, wrong = 0;
  for (int k = 0; k < 32; k++) {
    uint32_t v = *p;
    if (v != first) unstable++;
    if (v != pat)   wrong++;
  }
  neorv32_uart0_printf("  gravado %x | 1a leitura %x | leituras diferentes da 1a: %u/32 | diferentes do gravado: %u/32\n",
                       (unsigned)pat, (unsigned)first, (unsigned)unstable, (unsigned)wrong);
}


// Marca reconhecivel: cada palavra recebe 0xC0DE0000 + indice. Se uma leitura
// devolve outro valor com o mesmo prefixo, sabemos EXATAMENTE de qual indice ele
// veio -- isso separa aliasing de endereco (leu a palavra errada) de escrita
// perdida/corrompida (valor sem o prefixo).
#define TAG 0xC0DE0000u

// Valor gravado: TAG + i*STEP. Como STEP=0x55, palavras vizinhas diferem em
// VARIOS bits -- isso separa "leu o endereco errado" (o valor lido ainda e um
// multiplo valido de STEP, de outro indice) de "leu o dado errado" (o valor nao
// e multiplo de STEP). Com TAG+i, vizinhos diferiam so no bit 0 e as duas
// hipoteses ficavam indistinguiveis.
#define STEP 0x55u

static void unique_test(uint32_t off) {
  volatile uint32_t *p = (volatile uint32_t*)SDRAM_ADDR(off);
  uint32_t f0 = sdram_get_fault_count();
  for (uint32_t i = 0; i < NWORDS; i++) p[i] = TAG + i * STEP;
  uint32_t f_wr = sdram_get_fault_count() - f0;

  uint32_t bad = 0, wrong_addr = 0, bad_data = 0, shown = 0;
  for (uint32_t i = 0; i < NWORDS; i++) {
    uint32_t got = p[i];
    if (got == TAG + i * STEP) continue;
    bad++;
    uint32_t off_tag = got - TAG;
    if ((got & 0xFFFF0000u) == TAG && (off_tag % STEP) == 0 && (off_tag / STEP) < NWORDS) {
      wrong_addr++;
      if (shown < 6) {
        neorv32_uart0_printf("    i=%u -> ENDERECO: leu indice %u\n",
                             (unsigned)i, (unsigned)(off_tag / STEP));
        shown++;
      }
    } else {
      bad_data++;
      uint32_t want = TAG + i * STEP;
      uint32_t diff = got ^ want;
      for (int b = 0; b < 32; b++) {
        if (diff & (1u << b)) {
          bit_err[b]++;
          if (want & (1u << b)) st1[b]++; else st0[b]++;
        }
      }
      if (shown < 6) {
        neorv32_uart0_printf("    i=%u -> DADO: esperado %x lido %x (xor %x)\n",
                             (unsigned)i, (unsigned)(TAG + i * STEP), (unsigned)got, (unsigned)diff);
        shown++;
      }
    }
  }
  uint32_t f_rd = sdram_get_fault_count() - f0 - f_wr;
  neorv32_uart0_printf("  offset %x: %u/%u erradas | ENDERECO=%u DADO=%u | faults wr=%u rd=%u\n",
                       (unsigned)off, (unsigned)bad, (unsigned)NWORDS,
                       (unsigned)wrong_addr, (unsigned)bad_data, (unsigned)f_wr, (unsigned)f_rd);
}

// Escreve e confere UMA palavra por vez. Se isto passa mas unique_test falha, a
// escrita chega correta e algo posterior a destroi (alias de uma escrita seguinte,
// ou perda da pagina no PRECHARGE).
static void writeverify_test(uint32_t off) {
  volatile uint32_t *p = (volatile uint32_t*)SDRAM_ADDR(off);
  uint32_t bad = 0;
  for (uint32_t i = 0; i < NWORDS; i++) {
    p[i] = TAG + i;
    if (p[i] != TAG + i) bad++;
  }
  neorv32_uart0_printf("  offset %x: %u/%u erradas na conferencia imediata\n",
                       (unsigned)off, (unsigned)bad, (unsigned)NWORDS);
}


// Escreve UMA palavra por vez e, apos cada escrita, rele TODAS as ja gravadas,
// imprimindo o valor cru. Mostra em que momento uma palavra ja gravada e
// destruida -- e por qual escrita seguinte. '<' marca valor diferente do esperado.
static void clobber_test(uint32_t off) {
  volatile uint32_t *p = (volatile uint32_t*)SDRAM_ADDR(off);
  neorv32_uart0_printf("  offset %x\n", (unsigned)off);
  for (uint32_t n = 0; n < 6; n++) {
    p[n] = TAG + n;
    neorv32_uart0_printf("    apos escrever p[%u]:", (unsigned)n);
    for (uint32_t k = 0; k <= n; k++) {
      uint32_t v = p[k];
      neorv32_uart0_printf(" %x%s", (unsigned)v, (v == TAG + k) ? "" : "<");
    }
    neorv32_uart0_printf("\n");
  }
  neorv32_uart0_printf("    releitura 1:");
  for (uint32_t k = 0; k < 6; k++) neorv32_uart0_printf(" %x", (unsigned)p[k]);
  neorv32_uart0_printf("\n    releitura 2:");
  for (uint32_t k = 0; k < 6; k++) neorv32_uart0_printf(" %x", (unsigned)p[k]);
  neorv32_uart0_printf("\n");
}

int sdram_diag_run(void) {
  neorv32_uart0_printf("\n===== DIAGNOSTICO SDRAM =====\n");
  neorv32_uart0_printf("%u palavras de 32 bits por padrao, %u offsets\n",
                       (unsigned)NWORDS, (unsigned)NOFFSETS);

  for (int b = 0; b < 32; b++) bit_err[b] = 0;

  static const uint32_t pats[] = { 0x00000000u, 0xFFFFFFFFu, 0xAAAAAAAAu, 0x55555555u };
  static const char *names[]   = { "00000000", "ffffffff", "aaaaaaaa", "55555555" };
  uint32_t total_bad = 0, total_words = 0;

  neorv32_uart0_printf("\n-- A) palavras com erro, por padrao e offset\n");
  for (unsigned o = 0; o < NOFFSETS; o++) {
    neorv32_uart0_printf("  offset %x:", (unsigned)test_offsets[o]);
    for (unsigned k = 0; k < 4; k++) {
      uint32_t bad = pass_pattern(test_offsets[o], pats[k], 0);
      total_bad += bad; total_words += NWORDS;
      neorv32_uart0_printf(" %s=%u", names[k], (unsigned)bad);
    }
    uint32_t bad = pass_pattern(test_offsets[o], 0, 1);
    total_bad += bad; total_words += NWORDS;
    neorv32_uart0_printf(" endereco=%u\n", (unsigned)bad);
  }
  neorv32_uart0_printf("  TOTAL: %u palavras com erro em %u\n",
                       (unsigned)total_bad, (unsigned)total_words);

  neorv32_uart0_printf("\n-- B) mapa de erros por bit (DQ[31:0])\n");
  print_bit_map();

  // Soma por metade do barramento: cada chip x16 cobre uma metade.
  uint32_t lo = 0, hi = 0;
  for (int b = 0; b < 16; b++) lo += bit_err[b];
  for (int b = 16; b < 32; b++) hi += bit_err[b];
  neorv32_uart0_printf("  DQ[15:0] (chip baixo) = %u erros | DQ[31:16] (chip alto) = %u erros\n",
                       (unsigned)lo, (unsigned)hi);

  neorv32_uart0_printf("\n-- C) estabilidade de leitura (mesmo endereco, 32 leituras)\n");
  for (unsigned o = 0; o < NOFFSETS; o++) stability_test(test_offsets[o]);

  for (int b = 0; b < 32; b++) { bit_err[b] = 0; st0[b] = 0; st1[b] = 0; }
  neorv32_uart0_printf("\n-- E) valores unicos: aliasing vs escrita perdida\n");
  for (unsigned o = 0; o < NOFFSETS; o++) unique_test(test_offsets[o]);

  neorv32_uart0_printf("  mapa de bits SO do teste E:\n");
  print_bit_map();

  neorv32_uart0_printf("  bits com erro: bit / total / esp0-leu1 / esp1-leu0\n");
  for (int b = 0; b < 32; b++) if (bit_err[b])
    neorv32_uart0_printf("    DQ[%i]: %u  %u  %u\n", b, (unsigned)bit_err[b], (unsigned)st0[b], (unsigned)st1[b]);

  neorv32_uart0_printf("\n-- F) escrita + conferencia imediata, palavra a palavra\n");
  for (unsigned o = 0; o < NOFFSETS; o++) writeverify_test(test_offsets[o]);

  neorv32_uart0_printf("\n-- G) quem destroi o que (escrita a escrita, valor cru)\n");
  clobber_test(test_offsets[0]);
  clobber_test(test_offsets[1]);

  neorv32_uart0_printf("\n-- D) access faults retentados: %u\n",
                       (unsigned)sdram_get_fault_count());
  neorv32_uart0_printf("===== FIM (%s) =====\n", total_bad ? "FAIL" : "PASS");
  return total_bad == 0;
}
