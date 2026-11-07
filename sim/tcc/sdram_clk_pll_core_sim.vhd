-- ================================================================================ --
-- Stub de simulacao de sdram_clk_pll_core (NAO sintetizavel)                       --
-- -------------------------------------------------------------------------------- --
-- O PLL real (rtl/tcc/ip/sdram_clk_pll_core.vhd) instancia o ALTPLL da biblioteca     --
-- altera_mf, que o GHDL nao tem. Este stub tem a mesma entidade e as mesmas portas: --
-- c0 = clock de entrada defasado de 180 graus (os -10000 ps a 50 MHz da placa) e    --
-- locked sobe alguns ciclos depois de areset cair. Compilar este arquivo NO LUGAR   --
-- do rtl/tcc/ip/sdram_clk_pll_core.vhd (ver sim/tcc/run_soc_sim.sh).                     --
-- ================================================================================ --

library ieee;
use ieee.std_logic_1164.all;

entity sdram_clk_pll_core is
  port (
    areset : in  std_logic := '0';
    inclk0 : in  std_logic := '0';
    c0     : out std_logic;
    locked : out std_logic
  );
end sdram_clk_pll_core;

architecture sim of sdram_clk_pll_core is
  signal lock_cnt : natural range 0 to 16 := 0;
begin

  c0 <= not inclk0;

  lock_proc: process(areset, inclk0)
  begin
    if (areset = '1') then
      lock_cnt <= 0;
    elsif rising_edge(inclk0) then
      if (lock_cnt < 16) then
        lock_cnt <= lock_cnt + 1;
      end if;
    end if;
  end process lock_proc;

  locked <= '1' when (lock_cnt = 16) else '0';

end sim;
