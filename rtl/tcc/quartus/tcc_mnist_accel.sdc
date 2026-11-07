# -------------------------------------------------------------------------- #
# tcc_mnist_accel.sdc
# Restricoes de timing: clock de sistema = 50 MHz (oscilador CLOCK_50 da
# DE2-115) e interface SDRAM (2x ISSI IS42S16320D formando um barramento de
# 32 bits, clock em DRAM_CLK/PIN_AE5 vindo do PLL sdram_clk_pll_core).
#
# A versao anterior deste arquivo restringia APENAS clk_i. Com isso o Timing
# Analyzer nunca analisou o caminho FPGA<->chip SDRAM: o slack reportado
# cobria so a logica interna, e o fitter roteava os pinos de dado/endereco
# sem nenhuma meta de timing. Resultado pratico: a margem de captura das
# linhas de dado variava a cada recompilacao.
# -------------------------------------------------------------------------- #

# -------------------------------------------------------------------------- #
# Clocks
# -------------------------------------------------------------------------- #
create_clock -name clk_i -period 20.000 [get_ports {clk_i}]

derive_pll_clocks
derive_clock_uncertainty

# Clock que o chip SDRAM realmente enxerga: a saida do PLL levada ao pino
# DRAM_CLK. E declarado a partir do proprio pino para que os delays de I/O
# abaixo sejam medidos contra a borda que o chip usa.
create_generated_clock -name dram_clk_pin \
    -source [get_pins {sdram_clk_pll_inst|altpll_component|auto_generated|pll1|clk[0]}] \
    [get_ports {dram_clk_o}]

# -------------------------------------------------------------------------- #
# Parametros do IS42S16320D (-7 speed grade, como na DE2-115)
# CONFERIR no datasheet antes de confiar nos numeros: valores errados aqui dao
# falsa confianca, que e pior do que nao ter restricao nenhuma.
# -------------------------------------------------------------------------- #
set sdram_tsu  1.5   ;# setup de entrada do chip (dado/comando antes da borda)
set sdram_th   0.8   ;# hold de entrada do chip
set sdram_tac  5.4   ;# access time: dado valido apos a borda (CL=3)
set sdram_toh  2.7   ;# dado do chip permanece valido apos a borda

# Atraso de trilha na placa. A Terasic nao publica os comprimentos da DE2-115;
# estes valores sao estimativas conservadoras para trilhas curtas. Se vierem a
# ser medidos/obtidos, ajustar aqui.
set board_max  0.2
set board_min  0.1

# -------------------------------------------------------------------------- #
# Saidas do FPGA para o chip: endereco, banco, comando, mascara e dado escrito
# -------------------------------------------------------------------------- #
set sdram_out_ports [get_ports { \
    dram_addr_o[*] dram_ba_o[*] dram_cas_n_o dram_ras_n_o dram_we_n_o \
    dram_cs_n_o dram_cke_o dram_dqm_o[*] dram_dq_io[*] }]

set_output_delay -clock dram_clk_pin -max [expr {$sdram_tsu + $board_max}] $sdram_out_ports
set_output_delay -clock dram_clk_pin -min [expr {-$sdram_th - $board_min}] $sdram_out_ports

# -------------------------------------------------------------------------- #
# Entradas do chip para o FPGA: dado lido (mesmo barramento, bidirecional)
# -------------------------------------------------------------------------- #
set_input_delay -clock dram_clk_pin -max [expr {$sdram_tac + $board_max}] [get_ports {dram_dq_io[*]}]
set_input_delay -clock dram_clk_pin -min [expr {$sdram_toh + $board_min}] [get_ports {dram_dq_io[*]}]

# -------------------------------------------------------------------------- #
# Entradas assincronas: reset e UART RX nao sao caminhos sincronos
# -------------------------------------------------------------------------- #
set_false_path -from [get_ports {key_n[*]}]
set_false_path -from [get_ports {uart0_rxd_i}]

# LEDs sao indicadores visuais, sem requisito de timing
set_false_path -to [get_ports {ledg_o[*]}]
