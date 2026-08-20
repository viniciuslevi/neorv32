-- ================================================================================ --
-- NEORV32 SoC - Systolic Array Processing Element (PE)                              --
-- -------------------------------------------------------------------------------- --
-- Custom Processing Element for INT8 Matrix Operations                              --
-- Part of the AI Accelerator for Cyclone IV E                                      --
-- -------------------------------------------------------------------------------- --
-- Licensed under the BSD-3-Clause license                                          --
-- ================================================================================ --

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library neorv32;
use neorv32.neorv32_package.all;

entity neorv32_systolic_pe is
  generic (
    DATA_WIDTH : natural := 8;
    ACC_WIDTH  : natural := 32
  );
  port (
    clk_i   : in  std_ulogic;
    rstn_i  : in  std_ulogic;
    en_i    : in  std_ulogic;
    clr_i   : in  std_ulogic;

    a_in_i  : in  std_ulogic_vector(DATA_WIDTH-1 downto 0);
    w_in_i  : in  std_ulogic_vector(DATA_WIDTH-1 downto 0);
    p_in_i  : in  std_ulogic_vector(ACC_WIDTH-1 downto 0);

    a_out_o : out std_ulogic_vector(DATA_WIDTH-1 downto 0);
    w_out_o : out std_ulogic_vector(DATA_WIDTH-1 downto 0);
    p_out_o : out std_ulogic_vector(ACC_WIDTH-1 downto 0)
  );
end neorv32_systolic_pe;

architecture neorv32_systolic_pe_rtl of neorv32_systolic_pe is

  signal a_reg   : std_ulogic_vector(DATA_WIDTH-1 downto 0);
  signal w_reg   : std_ulogic_vector(DATA_WIDTH-1 downto 0);
  signal acc_reg : signed(ACC_WIDTH-1 downto 0);
  signal mult_res : signed(ACC_WIDTH-1 downto 0);

begin

  mult_res <= resize(signed(a_in_i) * signed(w_in_i), ACC_WIDTH);

  pe_process: process(rstn_i, clk_i)
  begin
    if (rstn_i = '0') then
      a_reg   <= (others => '0');
      w_reg   <= (others => '0');
      acc_reg <= (others => '0');
    elsif rising_edge(clk_i) then
      if (clr_i = '1') then
        acc_reg <= (others => '0');
        a_reg   <= (others => '0');
        w_reg   <= (others => '0');
      elsif (en_i = '1') then
        acc_reg <= signed(p_in_i) + mult_res;
        a_reg   <= a_in_i;
        w_reg   <= w_in_i;
      end if;
    end if;
  end process pe_process;

  a_out_o <= a_reg;
  w_out_o <= w_reg;
  p_out_o <= std_ulogic_vector(acc_reg);

end neorv32_systolic_pe_rtl;
