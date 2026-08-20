# -------------------------------------------------------------------------- #
# neorv32_mnist_accel.sdc
# Restricoes de timing: clock de sistema = 50 MHz (oscilador CLOCK_50 da
# DE2-115, sem PLL -- ver cabecalho de neorv32_de2115_mnist_top.vhd).
# -------------------------------------------------------------------------- #

create_clock -name clk_i -period 20.000 [get_ports {clk_i}]

derive_clock_uncertainty

# Entradas assincronas (reset, UART RX) nao sao caminhos de dados sincronos
set_false_path -from [get_ports {key_n[*]}]
set_false_path -from [get_ports {uart0_rxd_i}]
