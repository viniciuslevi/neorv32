-- ================================================================================ --
-- NEORV32 SoC - Systolic Array Accelerator (CFS Integration)                        --
-- -------------------------------------------------------------------------------- --
-- AI Accelerator integrating 8x8 systolic array with NEORV32 via CFS interface     --
-- Replaces the default neorv32_cfs module to provide systolic array functionality  --
-- -------------------------------------------------------------------------------- --
-- Register Map (word-addressed via addr(15 downto 2)):                            --
--   0x00  CTRL         [1] clear, [0] start                                       --
--   0x01  STATUS       [1] done,  [0] busy                                        --
--   0x02  WEIGHT_ADDR  Weight memory address                                       --
--   0x03  WEIGHT_DATA  Weight data write (INT8 in bits [7:0])                      --
--   0x04  ACT_ADDR     Activation memory address                                   --
--   0x05  ACT_DATA     Activation data write (INT8 in bits [7:0])                  --
--   0x06  RESULT_ADDR  Result memory address                                       --
--   0x07  RESULT_DATA  Result data read (INT32)                                    --
-- -------------------------------------------------------------------------------- --
-- Licensed under the BSD-3-Clause license                                          --
-- ================================================================================ --

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library neorv32;
use neorv32.neorv32_package.all;

entity neorv32_cfs is
  port (
    clk_i     : in  std_ulogic;
    rstn_i    : in  std_ulogic;
    bus_req_i : in  bus_req_t;
    bus_rsp_o : out bus_rsp_t;
    irq_o     : out std_ulogic;
    cfs_in_i  : in  std_ulogic_vector(255 downto 0);
    cfs_out_o : out std_ulogic_vector(255 downto 0)
  );
end neorv32_cfs;

architecture neorv32_cfs_rtl of neorv32_cfs is

  constant ARRAY_ROWS   : natural := 8;
  constant ARRAY_COLS   : natural := 8;
  constant DATA_WIDTH    : natural := 8;
  constant ACC_WIDTH     : natural := 32;
  constant WEIGHT_DEPTH  : natural := 10;
  constant ACT_DEPTH     : natural := 10;
  constant RESULT_DEPTH  : natural := 7;

  constant REG_CTRL        : natural := 0;
  constant REG_STATUS      : natural := 1;
  constant REG_WEIGHT_ADDR : natural := 2;
  constant REG_WEIGHT_DATA : natural := 3;
  constant REG_ACT_ADDR    : natural := 4;
  constant REG_ACT_DATA    : natural := 5;
  constant REG_RESULT_ADDR : natural := 6;
  constant REG_RESULT_DATA : natural := 7;

  signal ctrl_reg       : std_ulogic_vector(31 downto 0);
  signal status_reg     : std_ulogic_vector(31 downto 0);
  signal weight_addr_r  : std_ulogic_vector(WEIGHT_DEPTH-1 downto 0);
  signal act_addr_r     : std_ulogic_vector(ACT_DEPTH-1 downto 0);
  signal result_addr_r  : std_ulogic_vector(RESULT_DEPTH-1 downto 0);

  type weight_mem_t is array (0 to (2**WEIGHT_DEPTH)-1) of std_ulogic_vector(DATA_WIDTH-1 downto 0);
  type act_mem_t    is array (0 to (2**ACT_DEPTH)-1) of std_ulogic_vector(DATA_WIDTH-1 downto 0);
  type result_mem_t is array (0 to (2**RESULT_DEPTH)-1) of std_ulogic_vector(ACC_WIDTH-1 downto 0);

  signal weight_mem : weight_mem_t;
  signal act_mem    : act_mem_t;
  signal result_mem : result_mem_t;

  signal array_start : std_ulogic;
  signal array_clear : std_ulogic;
  signal array_done  : std_ulogic;
  signal array_busy  : std_ulogic;

  signal act_cols_to_array : std_ulogic_vector(ARRAY_COLS*DATA_WIDTH-1 downto 0);
  signal weight_to_array   : std_ulogic_vector(ARRAY_ROWS*ARRAY_COLS*DATA_WIDTH-1 downto 0);
  signal result_from_array : std_ulogic_vector(ARRAY_COLS*ACC_WIDTH-1 downto 0);

  type fsm_t is (S_IDLE, S_LOAD_WEIGHTS, S_LOAD_ACTS, S_COMPUTE, S_STORE_RESULTS, S_DONE);
  signal fsm_state : fsm_t;
  signal tile_row  : natural range 0 to ARRAY_ROWS-1;

  signal prev_done : std_ulogic;

begin

  cfs_out_o <= (others => '0');

  status_reg(0) <= array_busy;
  status_reg(1) <= array_done;

  irq_gen: process(rstn_i, clk_i)
  begin
    if (rstn_i = '0') then
      prev_done <= '0';
      irq_o     <= '0';
    elsif rising_edge(clk_i) then
      prev_done <= array_done;
      if (array_done = '1' and prev_done = '0') then
        irq_o <= '1';
      else
        irq_o <= '0';
      end if;
    end if;
  end process irq_gen;

  bus_access: process(rstn_i, clk_i)
    variable addr_idx : natural range 0 to 16383;
  begin
    if (rstn_i = '0') then
      ctrl_reg      <= (others => '0');
      weight_addr_r <= (others => '0');
      act_addr_r    <= (others => '0');
      result_addr_r <= (others => '0');
      bus_rsp_o     <= rsp_terminate_c;
    elsif rising_edge(clk_i) then
      bus_rsp_o.ack <= bus_req_i.stb;
      bus_rsp_o.err <= '0';
      bus_rsp_o.data <= (others => '0');

      if (bus_req_i.stb = '1') then
        addr_idx := to_integer(unsigned(bus_req_i.addr(15 downto 2)));

        if (bus_req_i.rw = '1') then
          case addr_idx is
            when REG_CTRL =>
              ctrl_reg <= bus_req_i.data;
            when REG_WEIGHT_ADDR =>
              weight_addr_r <= bus_req_i.data(WEIGHT_DEPTH-1 downto 0);
            when REG_WEIGHT_DATA =>
              weight_mem(to_integer(unsigned(weight_addr_r))) <= bus_req_i.data(DATA_WIDTH-1 downto 0);
              weight_addr_r <= std_ulogic_vector(unsigned(weight_addr_r) + 1);
            when REG_ACT_ADDR =>
              act_addr_r <= bus_req_i.data(ACT_DEPTH-1 downto 0);
            when REG_ACT_DATA =>
              act_mem(to_integer(unsigned(act_addr_r))) <= bus_req_i.data(DATA_WIDTH-1 downto 0);
              act_addr_r <= std_ulogic_vector(unsigned(act_addr_r) + 1);
            when REG_RESULT_ADDR =>
              result_addr_r <= bus_req_i.data(RESULT_DEPTH-1 downto 0);
            when others => null;
          end case;
        else
          case addr_idx is
            when REG_CTRL =>
              bus_rsp_o.data <= ctrl_reg;
            when REG_STATUS =>
              bus_rsp_o.data <= status_reg;
            when REG_WEIGHT_ADDR =>
              bus_rsp_o.data(WEIGHT_DEPTH-1 downto 0) <= weight_addr_r;
            when REG_WEIGHT_DATA =>
              bus_rsp_o.data(DATA_WIDTH-1 downto 0) <= weight_mem(to_integer(unsigned(weight_addr_r)));
            when REG_ACT_ADDR =>
              bus_rsp_o.data(ACT_DEPTH-1 downto 0) <= act_addr_r;
            when REG_ACT_DATA =>
              bus_rsp_o.data(DATA_WIDTH-1 downto 0) <= act_mem(to_integer(unsigned(act_addr_r)));
            when REG_RESULT_ADDR =>
              bus_rsp_o.data(RESULT_DEPTH-1 downto 0) <= result_addr_r;
            when REG_RESULT_DATA =>
              bus_rsp_o.data <= result_mem(to_integer(unsigned(result_addr_r)));
            when others =>
              bus_rsp_o.data <= (others => '0');
          end case;
        end if;
      end if;
    end if;
  end process bus_access;

  array_clear <= '1' when (ctrl_reg(1) = '1') else '0';

  compute_fsm: process(rstn_i, clk_i)
    variable start_req : std_ulogic;
  begin
    if (rstn_i = '0') then
      fsm_state <= S_IDLE;
      array_start <= '0';
      tile_row    <= 0;
      act_cols_to_array <= (others => '0');
      weight_to_array   <= (others => '0');
    elsif rising_edge(clk_i) then
      array_start <= '0';
      start_req := ctrl_reg(0) and (not array_busy) and (not array_clear);

      case fsm_state is
        when S_IDLE =>
          if (start_req = '1') then
            fsm_state <= S_LOAD_WEIGHTS;
            tile_row  <= 0;
          end if;

        when S_LOAD_WEIGHTS =>
          for i in 0 to ARRAY_ROWS*ARRAY_COLS-1 loop
            weight_to_array((i+1)*DATA_WIDTH-1 downto i*DATA_WIDTH) <=
              weight_mem(i);
          end loop;
          fsm_state <= S_LOAD_ACTS;

        when S_LOAD_ACTS =>
          for i in 0 to ARRAY_COLS-1 loop
            act_cols_to_array((i+1)*DATA_WIDTH-1 downto i*DATA_WIDTH) <=
              act_mem(tile_row * ARRAY_COLS + i);
          end loop;
          array_start <= '1';
          fsm_state <= S_COMPUTE;

        when S_COMPUTE =>
          if (array_done = '1') then
            for i in 0 to ARRAY_COLS-1 loop
              result_mem(tile_row * ARRAY_COLS + i) <=
                result_from_array((i+1)*ACC_WIDTH-1 downto i*ACC_WIDTH);
            end loop;
            fsm_state <= S_STORE_RESULTS;
          end if;

        when S_STORE_RESULTS =>
          if (tile_row < ARRAY_ROWS - 1) then
            tile_row <= tile_row + 1;
            fsm_state <= S_LOAD_ACTS;
          else
            fsm_state <= S_DONE;
          end if;

        when S_DONE =>
          fsm_state <= S_IDLE;

      end case;
    end if;
  end process compute_fsm;

  systolic_array_inst: entity work.neorv32_systolic_array
    generic map (
      ARRAY_ROWS => ARRAY_ROWS,
      ARRAY_COLS => ARRAY_COLS,
      DATA_WIDTH  => DATA_WIDTH,
      ACC_WIDTH   => ACC_WIDTH
    )
    port map (
      clk_i         => clk_i,
      rstn_i        => rstn_i,
      start_i       => array_start,
      clear_i       => array_clear,
      act_cols_i    => act_cols_to_array,
      weight_i      => weight_to_array,
      done_o        => array_done,
      busy_o        => array_busy,
      result_o      => result_from_array
    );

end neorv32_cfs_rtl;
