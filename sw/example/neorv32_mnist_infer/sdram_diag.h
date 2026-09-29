// ================================================================================ //
// Diagnostico da interface SDRAM (Fase 3/4 do TCC)                                 //
// -------------------------------------------------------------------------------- //
// Substitui o "smoke test" de 16 bytes de main.c por um teste que identifica QUAL  //
// parte da interface falha. A DE2-115 tem dois chips IS42S16320D x16 formando um   //
// barramento de 32 bits: DQ[15:0] em um chip, DQ[31:16] no outro. O controlador    //
// (neorv32_sdram_controller.vhd) faz um unico acesso de 32 bits, entao um erro      //
// confinado a uma metade do barramento aponta para um chip / meia-banda de pinos.  //
// ================================================================================ //
#ifndef SDRAM_DIAG_H
#define SDRAM_DIAG_H

// Roda a bateria completa e imprime o relatorio em UART0.
// Retorna 1 se tudo passou, 0 se houve qualquer erro.
int sdram_diag_run(void);

#endif // SDRAM_DIAG_H
