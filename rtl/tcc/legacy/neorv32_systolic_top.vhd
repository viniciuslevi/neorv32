-- ================================================================================ --
-- NEORV32 SoC - Systolic Array Top-Level Module                                     --
-- -------------------------------------------------------------------------------- --
-- Top-level accelerator with control FSM, weight/activation/input memories,        --
-- and memory-mapped register interface for NEORV32 integration                     --
-- Target: Cyclone IV E (DE2-115)                                                   --
-- -------------------------------------------------------------------------------- --
-- Register Map:                                                                     --
--   0x00  CTRL       [31:2] reserved, [1] clear, [0] start                         --
--   0x04  STATUS     [31:2] reserved, [1] done,  [0] busy                          --
--   0x08  WEIGHT_ADDR  Weight memory address (8 rows x 8 cols = 64 entries)        --
--   0x0C  WEIGHT_DATA  Weight data write (INT8)                                    --
--   0x10  ACT_ADDR     Activation memory address (8 rows x 8 cols = 64 entries)    --
--   0x14  ACT_DATA     Activation data write (INT8)                                --
--   0x18  RESULT_ADDR  Result memory address (8 cols = 8 entries)                  --
--   0x1C  RESULT_DATA  Result data read (INT32)                                    --
--   0x20  CONFIG       [31:16] rows, [15:0] cols (for tiled operation)             --
-- -------------------------------------------------------------------------------- --
-- Licensed under the BSD-3-Clause license                                          --
-- ================================================================================ --

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library neorv32;
use neorv32.neorv32_package.all;

entity neorv32_systolic_top is
  generic (
    ARRAY_ROWS : natural := 8;
    ARRAY_COLS : natural := 8;
    DATA_WIDTH  : natural := 8;
    ACC_WIDTH   : natural := 32;
    WEIGHT_DEPTH : natural := 10;
    ACT_DEPTH    : natural := 10;
    RESULT_DEPTH : natural := 4
  );
  port (
    clk_i   : in  std_ulogic;
    rstn_i  : in  std_ulogic;

    addr_i  : in  std_ulogic_vector(31 downto 0);
    wdata_i : in  std_ulogic_vector(31 downto 0);
    rdata_o : out std_ulogic_vector(31 downto 0);
    we_i    : in  std_ulogic;
    re_i    : in  std_ulogic;
    ack_o   : out std_ulogic;
    err_o   : out std_ulogic;

    done_o  : out std_ulogic;
    busy_o  : out std_ulogic
  );
end neorv32_systolic_top;

architecture neorv32_systolic_top_rtl of neorv32_systolic_top is

  constant REG_CTRL        : natural := 0;
  constant REG_STATUS      : natural := 1;
  constant REG_WEIGHT_ADDR : natural := 2;
  constant REG_WEIGHT_DATA : natural := 3;
  constant REG_ACT_ADDR    : natural := 4;
  constant REG_ACT_DATA    : natural := 5;
  constant REG_RESULT_ADDR : natural := 6;
  constant REG_RESULT_DATA : natural := 7;
  constant REG_CONFIG      : natural := 8;

  signal ctrl_reg    : std_ulogic_vector(31 downto 0);
  signal status_reg  : std_ulogic_vector(31 downto 0);
  signal config_reg  : std_ulogic_vector(31 downto 0);

  signal start_pulse  : std_ulogic;
  signal clear_pulse  : std_ulogic;

  type weight_mem_t is array (0 to (2**WEIGHT_DEPTH)-1) of std_ulogic_vector(DATA_WIDTH-1 downto 0);
  type act_mem_t    is array (0 to (2**ACT_DEPTH)-1) of std_ulogic_vector(DATA_WIDTH-1 downto 0);
  type result_mem_t is array (0 to (2**RESULT_DEPTH)-1) of std_ulogic_vector(ACC_WIDTH-1 downto 0);

  signal weight_mem : weight_mem_t;
  signal act_mem    : act_mem_t;
  signal result_mem : result_mem_t;

  signal weight_addr_reg : std_ulogic_vector(WEIGHT_DEPTH-1 downto 0);
  signal act_addr_reg    : std_ulogic_vector(ACT_DEPTH-1 downto 0);
  signal result_addr_reg : std_ulogic_vector(RESULT_DEPTH-1 downto 0);

  signal array_start  : std_ulogic;
  signal array_clear  : std_ulogic;
  signal array_done   : std_ulogic;
  signal array_busy   : std_ulogic;

  signal act_cols_to_array : std_ulogic_vector(ARRAY_COLS*DATA_WIDTH-1 downto 0);
  signal weight_to_array   : std_ulogic_vector(ARRAY_ROWS*ARRAY_COLS*DATA_WIDTH-1 downto 0);
  signal result_from_array : std_ulogic_vector(ARRAY_COLS*ACC_WIDTH-1 downto 0);

  type fsm_t is (S_IDLE, S_LOAD_WEIGHTS, S_LOAD_ACTS, S_COMPUTE, S_STORE_RESULTS, S_DONE);
  signal fsm_state : fsm_t;
  signal tile_row  : natural range 0 to ARRAY_ROWS-1;

begin

  done_o <= array_done;
  busy_o <= array_busy;

  ack_o <= '1' when (we_i = '1' or re_i = '1') else '0';
  err_o <= '0';

  start_pulse <= we_i when (to_integer(unsigned(addr_i(3 downto 0))) = REG_CTRL) else '0';
  clear_pulse <= '1' when (start_pulse = '1' and wdata_i(1) = '1') else '0';

  register_write: process(rstn_i, clk_i)
  begin
    if (rstn_i = '0') then
      ctrl_reg        <= (others => '0');
      config_reg      <= (others => '0');
      weight_addr_reg <= (others => '0');
      act_addr_reg    <= (others => '0');
      result_addr_reg <= (others => '0');
    elsif rising_edge(clk_i) then
      if (we_i = '1') then
        case to_integer(unsigned(addr_i(3 downto 0))) is
          when REG_CTRL =>
            ctrl_reg <= wdata_i;
          when REG_CONFIG =>
            config_reg <= wdata_i;
          when REG_WEIGHT_ADDR =>
            weight_addr_reg <= wdata_i(WEIGHT_DEPTH-1 downto 0);
          when REG_WEIGHT_DATA =>
            weight_mem(to_integer(unsigned(weight_addr_reg))) <= wdata_i(DATA_WIDTH-1 downto 0);
            weight_addr_reg <= std_ulogic_vector(unsigned(weight_addr_reg) + 1);
          when REG_ACT_ADDR =>
            act_addr_reg <= wdata_i(ACT_DEPTH-1 downto 0);
          when REG_ACT_DATA =>
            act_mem(to_integer(unsigned(act_addr_reg))) <= wdata_i(DATA_WIDTH-1 downto 0);
            act_addr_reg <= std_ulogic_vector(unsigned(act_addr_reg) + 1);
          when REG_RESULT_ADDR =>
            result_addr_reg <= wdata_i(RESULT_DEPTH-1 downto 0);
          when others => null;
        end case;
      end if;
    end if;
  end process register_write;

  register_read: process(addr_i, ctrl_reg, status_reg, config_reg, weight_addr_reg,
                         act_addr_reg, result_addr_reg, weight_mem, act_mem, result_mem)
    variable reg_idx : natural;
  begin
    rdata_o <= (others => '0');
    reg_idx := to_integer(unsigned(addr_i(3 downto 0)));
    case reg_idx is
      when REG_CTRL =>
        rdata_o <= ctrl_reg;
      when REG_STATUS =>
        rdata_o <= status_reg;
      when REG_CONFIG =>
        rdata_o <= config_reg;
      when REG_WEIGHT_ADDR =>
        rdata_o(WEIGHT_DEPTH-1 downto 0) <= weight_addr_reg;
      when REG_WEIGHT_DATA =>
        rdata_o(DATA_WIDTH-1 downto 0) <= weight_mem(to_integer(unsigned(weight_addr_reg)));
      when REG_ACT_ADDR =>
        rdata_o(ACT_DEPTH-1 downto 0) <= act_addr_reg;
      when REG_ACT_DATA =>
        rdata_o(DATA_WIDTH-1 downto 0) <= act_mem(to_integer(unsigned(act_addr_reg)));
      when REG_RESULT_ADDR =>
        rdata_o(RESULT_DEPTH-1 downto 0) <= result_addr_reg;
      when REG_RESULT_DATA =>
        rdata_o <= result_mem(to_integer(unsigned(result_addr_reg)));
      when others =>
        rdata_o <= (others => '0');
    end case;
  end process register_read;

  status_reg(0) <= array_busy;
  status_reg(1) <= array_done;

  array_clear <= clear_pulse;

  compute_fsm: process(rstn_i, clk_i)
  begin
    if (rstn_i = '0') then
      fsm_state <= S_IDLE;
      array_start <= '0';
      tile_row <= 0;
      for i in 0 to ARRAY_COLS-1 loop
        act_cols_to_array((i+1)*DATA_WIDTH-1 downto i*DATA_WIDTH) <= (others => '0');
      end loop;
      for i in 0 to ARRAY_ROWS*ARRAY_COLS-1 loop
        weight_to_array((i+1)*DATA_WIDTH-1 downto i*DATA_WIDTH) <= (others => '0');
      end loop;
    elsif rising_edge(clk_i) then
      array_start <= '0';

      case fsm_state is
        when S_IDLE =>
          if (start_pulse = '1' and ctrl_reg(0) = '1' and clear_pulse = '0') then
            fsm_state <= S_LOAD_WEIGHTS;
            tile_row <= 0;
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

  systolic_array_inst: entity work.tcc_systolic_array
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

end neorv32_systolic_top_rtl;
