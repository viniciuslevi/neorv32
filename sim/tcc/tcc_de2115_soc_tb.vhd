-- ================================================================================ --
-- Testbench do SoC: neorv32_de2115_mnist_top + modelo de SDRAM                     --
-- -------------------------------------------------------------------------------- --
-- Simula o top-level da placa inteiro: NEORV32 (com DMA e cache de instrucoes),    --
-- gateway XBUS, controlador SDRAM + modelo comportamental, acelerador sistolico.   --
-- O firmware vem da imagem gravada na IMEM (BOOT_MODE_SELECT = 2), compilado com   --
-- UART0_SIM_MODE: o texto da UART sai direto no console do simulador.              --
-- -------------------------------------------------------------------------------- --
-- Fim do teste: o firmware escreve um codigo em LEDG (GPIO[7:0]):                  --
--   0xA5 = PASS, 0xEE = FAIL. Qualquer outro valor ate MAX_MS = timeout.         --
-- Ver sim/tcc/run_soc_sim.sh e sw/tcc/accel_dma_test.                              --
-- ================================================================================ --

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

entity neorv32_de2115_soc_tb is
  generic (
    T        : natural := 8;       -- tamanho do array sistolico
    MAX_MS    : natural := 400;    -- tempo simulado maximo, em ms
    HEARTBEAT : time    := 1 ms;   -- intervalo do relatorio de progresso
    UART_LOG  : string  := "sim/build/soc_uart0"; -- + ".log": texto do pino TX
    -- Modelo de SDRAM (ver sim/tcc/tcc_sdram_model.vhd): linhas por banco e
    -- arquivos carregados no tempo 0 (pesos e imagem, no lugar do upload pela UART)
    SDRAM_ROW_BITS : natural := 4;
    SDRAM_INIT0    : string  := "";
    SDRAM_OFFS0    : natural := 0;
    SDRAM_INIT1    : string  := "";
    SDRAM_OFFS1    : natural := 0
  );
end neorv32_de2115_soc_tb;

architecture tb of neorv32_de2115_soc_tb is

  constant CLK_PERIOD : time := 20 ns; -- 50 MHz, como o CLOCK_50 da placa

  signal clk   : std_ulogic := '0';
  signal key_n : std_ulogic_vector(1 downto 0) := "10"; -- KEY[0] (reset) pressionado
  signal ledg  : std_ulogic_vector(7 downto 0);
  signal ledr  : std_ulogic_vector(7 downto 0);
  signal txd   : std_ulogic;

  signal dram_addr  : std_ulogic_vector(12 downto 0);
  signal dram_ba    : std_ulogic_vector(1 downto 0);
  signal dram_cas_n : std_ulogic;
  signal dram_cke   : std_ulogic;
  signal dram_clk   : std_ulogic;
  signal dram_cs_n  : std_ulogic;
  signal dram_dq    : std_logic_vector(31 downto 0);
  signal dram_dqm   : std_ulogic_vector(3 downto 0);
  signal dram_ras_n : std_ulogic;
  signal dram_we_n  : std_ulogic;

begin

  clk <= not clk after CLK_PERIOD / 2;

  dut: entity work.neorv32_de2115_mnist_top
    generic map (
      CLOCK_FREQUENCY  => 50_000_000,
      BOOT_MODE_SELECT => 2,
      ACCEL_ARRAY_SIZE => T
    )
    port map (
      clk_i        => clk,
      key_n        => key_n,
      uart0_txd_o  => txd,
      uart0_rxd_i  => '1',
      ledg_o       => ledg,
      lcd_data_o   => open,
      lcd_rs_o     => open,
      lcd_rw_o     => open,
      lcd_en_o     => open,
      lcd_on_o     => open,
      lcd_blon_o   => open,
      ledr_o       => ledr,
      dram_addr_o  => dram_addr,
      dram_ba_o    => dram_ba,
      dram_cas_n_o => dram_cas_n,
      dram_cke_o   => dram_cke,
      dram_clk_o   => dram_clk,
      dram_cs_n_o  => dram_cs_n,
      dram_dq_io   => dram_dq,
      dram_dqm_o   => dram_dqm,
      dram_ras_n_o => dram_ras_n,
      dram_we_n_o  => dram_we_n
    );

  -- Firmware compilado sem UART0_SIM_MODE manda o texto pelo pino TX, a 115200
  -- baud como na placa: este receptor o decodifica e grava em UART_LOG.log.
  uart_rx: entity work.sim_uart_rx
    generic map (
      NAME => UART_LOG,
      FCLK => 50.0e6,
      BAUD => 115200.0
    )
    port map (
      clk => clk,
      rxd => txd
    );

  sdram: entity work.neorv32_sdram_model
    generic map (
      ROW_BITS   => SDRAM_ROW_BITS,
      INIT_FILE0 => SDRAM_INIT0,
      INIT_OFFS0 => SDRAM_OFFS0,
      INIT_FILE1 => SDRAM_INIT1,
      INIT_OFFS1 => SDRAM_OFFS1
    )
    port map (
      dram_addr_i  => dram_addr,
      dram_ba_i    => dram_ba,
      dram_cas_n_i => dram_cas_n,
      dram_cke_i   => dram_cke,
      dram_clk_i   => dram_clk,
      dram_cs_n_i  => dram_cs_n,
      dram_dq_io   => dram_dq,
      dram_dqm_i   => dram_dqm,
      dram_ras_n_i => dram_ras_n,
      dram_we_n_i  => dram_we_n
    );

  -- O texto da UART (modo de simulacao) sai pelo stdout, que o GHDL bufferiza
  -- quando a saida vai para um pipe ou arquivo; o report vai para o stderr e
  -- aparece na hora. Batimento a cada HEARTBEAT de tempo simulado, com LEDG
  -- (o firmware escreve ali a etapa em que esta).
  progress: process
  begin
    wait for HEARTBEAT;
    report "[tb] " & time'image(now) & "  LEDG = 0x" & to_hstring(ledg);
  end process;

  stim: process
  begin
    key_n <= "10";
    wait for CLK_PERIOD * 20;
    key_n <= "11"; -- solta o reset
    wait until (ledg = x"A5") or (ledg = x"EE") for MAX_MS * 1 ms;
    if ledg = x"A5" then
      report "=== neorv32_de2115_soc_tb (" & integer'image(T) & "x" & integer'image(T) &
             "): firmware reportou PASS em " & time'image(now) & " ===";
    elsif ledg = x"EE" then
      report "=== neorv32_de2115_soc_tb (" & integer'image(T) & "x" & integer'image(T) &
             "): firmware reportou FAIL em " & time'image(now) & " ===" severity error;
    else
      report "=== neorv32_de2115_soc_tb: TIMEOUT (LEDG = 0x" & to_hstring(ledg) & ") ===" severity error;
    end if;
    std.env.stop;
  end process;

end tb;
