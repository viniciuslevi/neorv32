// Compila o driver do firmware de inferencia dentro deste exemplo.
//
// Nao listar ../neorv32_mnist_infer/accel_driver.c em APP_SRC: o common.mk poe as
// pastas das fontes no VPATH, e o make passava a achar o main.elf DAQUELA pasta
// como alvo ja pronto -- a imagem da IMEM saia do firmware de inferencia, sem
// compilar este teste.
#include "../neorv32_mnist_infer/accel_driver.c"
