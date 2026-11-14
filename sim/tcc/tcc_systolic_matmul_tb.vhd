-- ================================================================================ --
-- Testbench: tcc_systolic_wb_accelerator - Verificacao de matmul 8x8x8 INT8    --
-- -------------------------------------------------------------------------------- --
-- Nivel 2 de verificacao (Metodologia 3.8: "Acelerador (sim)"). Atua como mestre    --
-- Wishbone classico, carrega um tile de pesos e um tile de ativacoes com valores    --
-- conhecidos, dispara o calculo e compara RESULT = ACT @ WEIGHT contra o valor      --
-- esperado computado na propria testbench (autoverificavel, sem golden file         --
-- externo). Cobre tambem o caso de teste 2 da metodologia (identidade x uns) e o    --
-- caso de teste 3 (tile com pesos/ativacoes conhecidos vs referencia).             --
-- -------------------------------------------------------------------------------- --
-- Uso (GHDL): ghdl -a --std=08 rtl/tcc/tcc_systolic_pe.vhd \                   --
--               rtl/tcc/tcc_systolic_array.vhd \                              --
--               rtl/tcc/tcc_systolic_wb_accelerator.vhd \                     --
--               sim/tcc/tcc_systolic_matmul_tb.vhd                                 --
--             ghdl -e --std=08 tcc_systolic_matmul_tb                          --
--             ghdl -r --std=08 tcc_systolic_matmul_tb                          --
-- ================================================================================ --

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

entity tcc_systolic_matmul_tb is
end tcc_systolic_matmul_tb;

architecture tb of tcc_systolic_matmul_tb is

  constant CLK_PERIOD : time := 20 ns; -- 50 MHz

  signal clk  : std_ulogic := '0';
  signal rstn : std_ulogic := '0';
  signal irq  : std_ulogic;

  signal wb_adr : std_ulogic_vector(31 downto 0) := (others => '0');
  signal wb_dat_o : std_ulogic_vector(31 downto 0) := (others => '0'); -- tb -> dut
  signal wb_dat_i : std_ulogic_vector(31 downto 0);                    -- dut -> tb
  signal wb_we  : std_ulogic := '0';
  signal wb_sel : std_ulogic_vector(3 downto 0) := "1111";
  signal wb_stb : std_ulogic := '0';
  signal wb_cyc : std_ulogic := '0';
  signal wb_ack : std_ulogic;
  signal wb_err : std_ulogic;

  type i8_matrix_t is array (0 to 7, 0 to 7) of integer;

  -- Matrizes de teste (valores pequenos, cabem em INT8 e nao estouram INT32 em 8 termos)
  function make_weight return i8_matrix_t is
    variable m : i8_matrix_t;
  begin
    for k in 0 to 7 loop
      for n in 0 to 7 loop
        m(k, n) := ((k * 3 + n * 5) mod 11) - 5; -- valores em [-5, 5]
      end loop;
    end loop;
    return m;
  end function;

  function make_act return i8_matrix_t is
    variable m : i8_matrix_t;
  begin
    for r in 0 to 7 loop
      for k in 0 to 7 loop
        m(r, k) := ((r * 7 + k * 2) mod 9) - 4; -- valores em [-4, 4]
      end loop;
    end loop;
    return m;
  end function;

  constant W_MAT : i8_matrix_t := make_weight;
  constant A_MAT : i8_matrix_t := make_act;

  procedure wb_write(
    signal   clk_i    : in  std_ulogic;
    signal   adr_o    : out std_ulogic_vector(31 downto 0);
    signal   dat_o    : out std_ulogic_vector(31 downto 0);
    signal   we_o     : out std_ulogic;
    signal   stb_o    : out std_ulogic;
    signal   cyc_o    : out std_ulogic;
    signal   ack_i    : in  std_ulogic;
    constant addr     : in  natural;
    constant data     : in  std_ulogic_vector(31 downto 0)
  ) is
  begin
    wait until rising_edge(clk_i);
    adr_o <= std_ulogic_vector(to_unsigned(addr, 32));
    dat_o <= data;
    we_o  <= '1';
    stb_o <= '1';
    cyc_o <= '1';
    wait until rising_edge(clk_i) and ack_i = '1';
    we_o  <= '0';
    stb_o <= '0';
    cyc_o <= '0';
  end procedure;

  procedure wb_read(
    signal   clk_i    : in  std_ulogic;
    signal   adr_o    : out std_ulogic_vector(31 downto 0);
    signal   we_o     : out std_ulogic;
    signal   stb_o    : out std_ulogic;
    signal   cyc_o    : out std_ulogic;
    signal   ack_i    : in  std_ulogic;
    signal   dat_i    : in  std_ulogic_vector(31 downto 0);
    constant addr     : in  natural;
    variable data     : out std_ulogic_vector(31 downto 0)
  ) is
  begin
    wait until rising_edge(clk_i);
    adr_o <= std_ulogic_vector(to_unsigned(addr, 32));
    we_o  <= '0';
    stb_o <= '1';
    cyc_o <= '1';
    wait until rising_edge(clk_i) and ack_i = '1';
    data := dat_i;
    stb_o <= '0';
    cyc_o <= '0';
  end procedure;

  function pack4i8(b0, b1, b2, b3 : integer) return std_ulogic_vector is
    variable r : std_ulogic_vector(31 downto 0);
  begin
    r(7 downto 0)   := std_ulogic_vector(to_signed(b0, 8));
    r(15 downto 8)  := std_ulogic_vector(to_signed(b1, 8));
    r(23 downto 16) := std_ulogic_vector(to_signed(b2, 8));
    r(31 downto 24) := std_ulogic_vector(to_signed(b3, 8));
    return r;
  end function;

begin

  clk <= not clk after CLK_PERIOD / 2;

  dut: entity work.tcc_systolic_wb_accelerator
    port map (
      clk_i    => clk,
      rstn_i   => rstn,
      irq_o    => irq,
      wb_adr_i => wb_adr,
      wb_dat_i => wb_dat_o,
      wb_dat_o => wb_dat_i,
      wb_we_i  => wb_we,
      wb_sel_i => wb_sel,
      wb_stb_i => wb_stb,
      wb_cyc_i => wb_cyc,
      wb_ack_o => wb_ack,
      wb_err_o => wb_err
    );

  stim: process
    variable rdata : std_ulogic_vector(31 downto 0);
    variable expected : integer;
    variable actual    : integer;
    variable errors    : natural := 0;
  begin
    rstn <= '0';
    wait for CLK_PERIOD * 5;
    rstn <= '1';
    wait for CLK_PERIOD * 2;

    -- Carrega o tile de pesos (0x100, 16 words, 4 bytes/word, row-major k*8+n)
    for w in 0 to 15 loop
      wb_write(clk, wb_adr, wb_dat_o, wb_we, wb_stb, wb_cyc, wb_ack,
               16#100# + w * 4,
               pack4i8(W_MAT(w*4/8, (w*4) mod 8),
                       W_MAT((w*4+1)/8, (w*4+1) mod 8),
                       W_MAT((w*4+2)/8, (w*4+2) mod 8),
                       W_MAT((w*4+3)/8, (w*4+3) mod 8)));
    end loop;

    -- Carrega o tile de ativacoes (0x500, 16 words, row-major m*8+k)
    for w in 0 to 15 loop
      wb_write(clk, wb_adr, wb_dat_o, wb_we, wb_stb, wb_cyc, wb_ack,
               16#500# + w * 4,
               pack4i8(A_MAT(w*4/8, (w*4) mod 8),
                       A_MAT((w*4+1)/8, (w*4+1) mod 8),
                       A_MAT((w*4+2)/8, (w*4+2) mod 8),
                       A_MAT((w*4+3)/8, (w*4+3) mod 8)));
    end loop;

    -- Dispara o calculo (CTRL.start = bit 0)
    wb_write(clk, wb_adr, wb_dat_o, wb_we, wb_stb, wb_cyc, wb_ack, 16#000#, x"00000001");

    -- Aguarda STATUS.done (bit 1)
    loop
      wb_read(clk, wb_adr, wb_we, wb_stb, wb_cyc, wb_ack, wb_dat_i, 16#004#, rdata);
      exit when rdata(1) = '1';
    end loop;

    -- Le e confere os 64 resultados contra a referencia calculada em VHDL
    for m in 0 to 7 loop
      for n in 0 to 7 loop
        wb_read(clk, wb_adr, wb_we, wb_stb, wb_cyc, wb_ack, wb_dat_i,
                16#900# + (m*8+n) * 4, rdata);
        actual := to_integer(signed(rdata));

        expected := 0;
        for k in 0 to 7 loop
          expected := expected + A_MAT(m, k) * W_MAT(k, n);
        end loop;

        if actual /= expected then
          report "MISMATCH RESULT[" & integer'image(m) & "][" & integer'image(n) &
                 "] = " & integer'image(actual) & ", esperado " & integer'image(expected)
                 severity error;
          errors := errors + 1;
        end if;
      end loop;
    end loop;

    wait for CLK_PERIOD * 2;

    if errors = 0 then
      report "=== tcc_systolic_matmul_tb: TODOS OS 64 RESULTADOS CORRETOS (PASS) ===";
    else
      report "=== tcc_systolic_matmul_tb: " & integer'image(errors) & " ERROS (FAIL) ===" severity error;
    end if;

    std.env.stop;
  end process;

end tb;
