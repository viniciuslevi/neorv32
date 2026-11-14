-- ================================================================================ --
-- Standalone Testbench - Systolic Array Wishbone Accelerator                        --
-- -------------------------------------------------------------------------------- --
-- Tests:                                                                            --
--   1. Register R/W (CTRL, STATUS, CONFIG)                                          --
--   2. Weight memory write/read with 4xINT8 packing                                 --
--   3. Activation memory write/read with 4xINT8 packing                             --
--   4. Matrix multiply: C = A x B (identity matrix test)                            --
--   5. IRQ assertion on compute done                                                --
--   6. Result readback verification                                                 --
-- ================================================================================ --

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library neorv32;
use neorv32.neorv32_package.all;

entity neorv32_systolic_wb_accelerator_tb is
end neorv32_systolic_wb_accelerator_tb;

architecture tb_rtl of neorv32_systolic_wb_accelerator_tb is

  constant CLOCK_FREQUENCY : natural := 100_000_000;
  constant f_period_c      : time    := (1 sec) / CLOCK_FREQUENCY;
  constant ACCEL_BASE      : std_ulogic_vector(31 downto 0) := x"80000000";

  signal clk_i, rstn_i : std_ulogic;
  signal irq_o         : std_ulogic;

  signal wb_adr_i  : std_ulogic_vector(31 downto 0);
  signal wb_dat_i  : std_ulogic_vector(31 downto 0);
  signal wb_dat_o  : std_ulogic_vector(31 downto 0);
  signal wb_we_i   : std_ulogic;
  signal wb_sel_i  : std_ulogic_vector(3 downto 0);
  signal wb_stb_i  : std_ulogic;
  signal wb_cyc_i  : std_ulogic;
  signal wb_ack_o  : std_ulogic;
  signal wb_err_o  : std_ulogic;

  signal test_done : std_ulogic := '0';
  signal test_pass : std_ulogic := '1';

begin

  clk_gen   <= (not clk_gen) and test_done after (f_period_c/2);
  rstn_i    <= '0', '1' after 30*(f_period_c/2);

  dut: entity work.neorv32_systolic_wb_accelerator
    port map (
      clk_i    => clk_i,
      rstn_i   => rstn_i,
      irq_o    => irq_o,
      wb_adr_i => wb_adr_i,
      wb_dat_i => wb_dat_i,
      wb_dat_o => wb_dat_o,
      wb_we_i  => wb_we_i,
      wb_sel_i => wb_sel_i,
      wb_stb_i => wb_stb_i,
      wb_cyc_i => wb_cyc_i,
      wb_ack_o => wb_ack_o,
      wb_err_o => wb_err_o
    );

  stim: process

    variable v_data : std_ulogic_vector(31 downto 0);

    procedure wb_write(
      addr : std_ulogic_vector(31 downto 0);
      data : std_ulogic_vector(31 downto 0)
    ) is
    begin
      wb_adr_i <= addr;
      wb_dat_i <= data;
      wb_we_i  <= '1';
      wb_sel_i <= x"F";
      wb_cyc_i <= '1';
      wb_stb_i <= '1';
      wait until rising_edge(clk_i) and wb_ack_o = '1';
      wait until rising_edge(clk_i);
      wb_stb_i <= '0';
      wb_cyc_i <= '0';
      wb_we_i  <= '0';
    end procedure;

    procedure wb_read(
      addr : std_ulogic_vector(31 downto 0);
      data : out std_ulogic_vector(31 downto 0)
    ) is
    begin
      wb_adr_i <= addr;
      wb_dat_i <= (others => '0');
      wb_we_i  <= '0';
      wb_sel_i <= x"F";
      wb_cyc_i <= '1';
      wb_stb_i <= '1';
      wait until rising_edge(clk_i) and wb_ack_o = '1';
      data := wb_dat_o;
      wait until rising_edge(clk_i);
      wb_stb_i <= '0';
      wb_cyc_i <= '0';
    end procedure;

    procedure check(label : string; actual, expected : std_ulogic_vector(31 downto 0)) is
    begin
      if (actual /= expected) then
        report "[FAIL] " & label &
               " expected=0x" & to_hstring(expected) &
               " got=0x" & to_hstring(actual)
          severity error;
        test_pass <= '0';
      else
        report "[PASS] " & label severity note;
      end if;
    end procedure;

    procedure wait_cycles(n : positive) is
    begin
      for i in 1 to n loop
        wait until rising_edge(clk_i);
      end loop;
    end procedure;

    constant ADDR_CTRL   : std_ulogic_vector(31 downto 0) := ACCEL_BASE + x"000";
    constant ADDR_STATUS : std_ulogic_vector(31 downto 0) := ACCEL_BASE + x"004";
    constant ADDR_CONFIG : std_ulogic_vector(31 downto 0) := ACCEL_BASE + x"008";

  begin
    wb_adr_i <= (others => '0');
    wb_dat_i <= (others => '0');
    wb_we_i  <= '0';
    wb_sel_i <= (others => '0');
    wb_stb_i <= '0';
    wb_cyc_i <= '0';

    wait until rstn_i = '1';
    wait_cycles(10);

    report "=== TEST 1: Register R/W ===" severity note;

    wb_write(ADDR_CTRL, x"00000005");
    wb_read(ADDR_CTRL, v_data);
    check("CTRL write/read", v_data, x"00000005");

    wb_write(ADDR_CTRL, x"00000000");
    wb_read(ADDR_STATUS, v_data);
    check("STATUS idle (busy=0, done=0)", v_data, x"00000000");

    wb_write(ADDR_CONFIG, x"00000007");
    wb_read(ADDR_CONFIG, v_data);
    check("CONFIG write/read", v_data, x"00000007");

    report "=== TEST 2: Weight memory write/read ===" severity note;

    for i in 0 to 15 loop
      v_data := std_ulogic_vector(to_unsigned(i*4+0, 8)) &
                std_ulogic_vector(to_unsigned(i*4+1, 8)) &
                std_ulogic_vector(to_unsigned(i*4+2, 8)) &
                std_ulogic_vector(to_unsigned(i*4+3, 8));
      wb_write(ACCEL_BASE + x"100" + std_ulogic_vector(to_unsigned(i*4, 32)), v_data);
    end loop;

    wb_read(ACCEL_BASE + x"100", v_data);
    check("WEIGHT[0] read", v_data, x"03020100");
    wb_read(ACCEL_BASE + x"13C", v_data);
    check("WEIGHT[15] read", v_data, x"3F3E3D3C");

    report "=== TEST 3: Activation memory write/read ===" severity note;

    for i in 0 to 15 loop
      v_data := std_ulogic_vector(to_unsigned(i*4+0, 8)) &
                std_ulogic_vector(to_unsigned(i*4+1, 8)) &
                std_ulogic_vector(to_unsigned(i*4+2, 8)) &
                std_ulogic_vector(to_unsigned(i*4+3, 8));
      wb_write(ACCEL_BASE + x"500" + std_ulogic_vector(to_unsigned(i*4, 32)), v_data);
    end loop;

    wb_read(ACCEL_BASE + x"500", v_data);
    check("ACT[0] read", v_data, x"03020100");

    report "=== TEST 4: Identity matrix multiply ===" severity note;

    wb_write(ADDR_CTRL, x"00000002");
    wait_cycles(5);

    for i in 0 to 15 loop
      v_data := (others => '0');
      wb_write(ACCEL_BASE + x"100" + std_ulogic_vector(to_unsigned(i*4, 32)), v_data);
    end loop;

    for i in 0 to 7 loop
      v_data := (others => '0');
      for b in 0 to 3 loop
        if (i mod 4 = b) then
          v_data((b+1)*8-1 downto b*8) := x"01";
        else
          v_data((b+1)*8-1 downto b*8) := x"00";
        end if;
      end loop;
      wb_write(ACCEL_BASE + x"100" + std_ulogic_vector(to_unsigned(i*4, 32)), v_data);
    end loop;

    for i in 0 to 15 loop
      v_data := std_ulogic_vector(to_unsigned(1, 8)) &
                std_ulogic_vector(to_unsigned(1, 8)) &
                std_ulogic_vector(to_unsigned(1, 8)) &
                std_ulogic_vector(to_unsigned(1, 8));
      wb_write(ACCEL_BASE + x"500" + std_ulogic_vector(to_unsigned(i*4, 32)), v_data);
    end loop;

    wb_write(ADDR_CTRL, x"00000001");
    wait_cycles(2);

    loop
      wb_read(ADDR_STATUS, v_data);
      exit when v_data(1) = '1';
      wait_cycles(50);
    end loop;

    check("STATUS done=1", v_data, x"00000002");
    report "Compute finished" severity note;

    for i in 0 to 7 loop
      wb_read(ACCEL_BASE + x"900" + std_ulogic_vector(to_unsigned(i*4, 32)), v_data);
      check("RESULT[" & integer'image(i) & "] = 1", v_data, x"00000001");
    end loop;

    report "=== TEST 5: IRQ assertion ===" severity note;
    check("IRQ pending in STATUS", irq_o, '1');

    wb_read(ADDR_STATUS, v_data);
    check("STATUS[2] irq_pending", v_data(2), '1');

    wb_write(ADDR_CTRL, x"00000004");
    wait_cycles(2);
    check("IRQ cleared", irq_o, '0');

    report "=== TEST 6: Bus error on invalid address ===" severity note;
    wb_read(ACCEL_BASE + x"400", v_data);
    check("ERR on gap address", wb_err_o, '1');

    report "=== ALL TESTS COMPLETED ===" severity note;
    if (test_pass = '1') then
      report "ALL TESTS PASSED" severity note;
    else
      report "SOME TESTS FAILED" severity error;
    end if;

    test_done <= '1';
    wait;
  end process stim;

end tb_rtl;
