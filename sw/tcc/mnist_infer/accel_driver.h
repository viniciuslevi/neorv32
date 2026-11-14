// ================================================================================ //
// NEORV32 MNIST Inference (Fase 3/4 do TCC) - Driver do acelerador sistolico       //
// -------------------------------------------------------------------------------- //
// Interface de baixo nivel com tcc_systolic_wb_accelerator.vhd (janela         //
// CTRL/STATUS/WEIGHT/ACT/RESULT) e uma multiplicacao de matrizes INT8 generica     //
// em tiles de 8x8, com correcao de zero-point (quantizacao assimetrica TFLite).    //
// ================================================================================ //
#ifndef ACCEL_DRIVER_H
#define ACCEL_DRIVER_H

#include <stdint.h>

#define ACCEL_BASE 0x90000000u

// Multiplica A(M x K) por W(K x N), ambos INT8, com zero-point de entrada zp_a
// (o peso W e assumido com zero-point 0, convencao padrao de quantizacao INT8
// do TFLite para pesos). Acumula em C (M x N), INT32, RAW (sem bias, sem
// requantizacao) -- isso e responsabilidade da camada acima (inference.c).
//
// A, W e C sao ponteiros para memoria linear (SDRAM ou SRAM interna):
//   A[m*K + k], W[k*N + n], C[m*N + n]
//
// M, K, N nao precisam ser multiplos de 8: os tiles de borda sao
// preenchidos com zero automaticamente.
void accel_matmul_i8(const int8_t *A, uint32_t M, uint32_t K,
                      const int8_t *W, uint32_t N,
                      int32_t zp_a,
                      int32_t *C);

#endif // ACCEL_DRIVER_H
