-- ================================================================================ --
-- NEORV32 SoC - Systolic Array 8x8 for AI Acceleration                             --
-- -------------------------------------------------------------------------------- --
-- 8x8 Weight-Stationary Systolic Array for INT8 Matrix Operations                  --
-- Part of the AI Accelerator for Cyclone IV E                                      --
-- -------------------------------------------------------------------------------- --
-- Data flow:                                                                        --
--   Activations: horizontal (left -> right), skewed by row index (one input        --
--                stream per PE row, entering at column 0, one column per cycle)    --
--   Partial sums: vertical (top -> bottom), accumulated per column                 --
--   Weights: full ARRAY_ROWSxARRAY_COLS tile pre-loaded into PEs                   --
--            (weight-stationary mode, one independent value per PE)                --
-- -------------------------------------------------------------------------------- --
-- One start_i pulse multiplies one activation ROW VECTOR (act_cols_i, one INT8     --
-- per PE row) by the full stationary weight tile, producing one INT32 result       --
-- per column: result_o(col) = sum_row act_cols_i(row) * weight_i(row,col).         --
-- Driving the array once per row of an 8x8 activation tile (weight loaded only     --
-- on the first call) yields a full 8x8 @ 8x8 -> 8x8 INT8 matrix multiplication.    --
-- -------------------------------------------------------------------------------- --
-- NOTE: earlier revisions of this file exposed weight_rows_i as a single           --
-- ARRAY_ROWS-wide vector broadcast to every column of a row, which could only      --
-- realize a matrix-vector product (all output columns held identical values).     --
-- weight_i now carries one independent INT8 value per PE (row,col), enabling      --
-- true matrix-matrix tiles as required for CNN/FC layers (TCC Fase 3/4).          --
-- -------------------------------------------------------------------------------- --
-- Licensed under the BSD-3-Clause license                                          --
-- ================================================================================ --

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library neorv32;
use neorv32.neorv32_package.all;

entity neorv32_systolic_array is
  generic (
    ARRAY_ROWS : natural := 8;
    ARRAY_COLS : natural := 8;
    DATA_WIDTH  : natural := 8;
    ACC_WIDTH   : natural := 32
  );
  port (
    clk_i         : in  std_ulogic;
    rstn_i        : in  std_ulogic;

    start_i       : in  std_ulogic;
    clear_i       : in  std_ulogic;

    act_cols_i    : in  std_ulogic_vector(ARRAY_COLS*DATA_WIDTH-1 downto 0);
    weight_i      : in  std_ulogic_vector(ARRAY_ROWS*ARRAY_COLS*DATA_WIDTH-1 downto 0);

    done_o        : out std_ulogic;
    busy_o        : out std_ulogic;

    result_o      : out std_ulogic_vector(ARRAY_COLS*ACC_WIDTH-1 downto 0)
  );
end neorv32_systolic_array;

architecture neorv32_systolic_array_rtl of neorv32_systolic_array is

  -- "Array de arrays" (nao array 2D verdadeiro) por portabilidade: elementos
  -- individuais sao pilotados por processos/instancias distintas geradas via
  -- "generate", uma por (row,col). Um array 2D genuino (array(A,B) of T) faz
  -- alguns simuladores (ex.: GHDL) reportarem "several sources for unresolved
  -- signal" nesse padrao, mesmo com indices estaticos por elemento -- o
  -- Quartus sintetiza de qualquer forma (nao ha resolucao de sinal em
  -- sintese), mas a simulacao falha na elaboracao. Array-de-arrays e o padrao
  -- portavel equivalente.
  type act_row_t  is array (0 to ARRAY_COLS-1) of std_ulogic_vector(DATA_WIDTH-1 downto 0);
  type act_2d_t   is array (0 to ARRAY_ROWS-1) of act_row_t;
  type psum_row_t is array (0 to ARRAY_COLS-1) of std_ulogic_vector(ACC_WIDTH-1 downto 0);
  type psum_2d_t  is array (0 to ARRAY_ROWS-1) of psum_row_t;

  signal pe_a_out  : act_2d_t;
  signal pe_w_out  : act_2d_t;
  signal pe_p_out  : psum_2d_t;

  signal a_in_pe   : act_2d_t;
  signal w_in_pe   : act_2d_t;
  signal p_in_pe   : psum_2d_t;

  signal weight_loaded : std_ulogic;
  signal pe_weight_reg : act_2d_t;

  signal busy_reg : std_ulogic;
  signal done_reg : std_ulogic;
  signal cycle_cnt : natural range 0 to ARRAY_ROWS + ARRAY_COLS + 1;

  signal act_skew_regs : act_2d_t;

begin

  busy_o <= busy_reg;
  done_o <= done_reg;

  ctrl_fsm: process(rstn_i, clk_i)
  begin
    if (rstn_i = '0') then
      busy_reg     <= '0';
      done_reg     <= '0';
      weight_loaded <= '0';
      cycle_cnt    <= 0;
      for row in 0 to ARRAY_ROWS-1 loop
        for col in 0 to ARRAY_COLS-1 loop
          pe_weight_reg(row)(col) <= (others => '0');
        end loop;
      end loop;
    elsif rising_edge(clk_i) then
      if (clear_i = '1') then
        busy_reg      <= '0';
        done_reg      <= '0';
        weight_loaded <= '0';
        cycle_cnt     <= 0;
        for row in 0 to ARRAY_ROWS-1 loop
          for col in 0 to ARRAY_COLS-1 loop
            pe_weight_reg(row)(col) <= (others => '0');
          end loop;
        end loop;
      elsif (start_i = '1' and busy_reg = '0') then
        -- Load one independent INT8 weight per PE from the flattened tile.
        -- Layout: weight_i((row*ARRAY_COLS+col+1)*DATA_WIDTH-1 downto (row*ARRAY_COLS+col)*DATA_WIDTH)
        for row in 0 to ARRAY_ROWS-1 loop
          for col in 0 to ARRAY_COLS-1 loop
            pe_weight_reg(row)(col) <=
              weight_i((row*ARRAY_COLS+col+1)*DATA_WIDTH-1 downto (row*ARRAY_COLS+col)*DATA_WIDTH);
          end loop;
        end loop;
        weight_loaded <= '1';
        busy_reg      <= '1';
        done_reg      <= '0';
        cycle_cnt     <= 0;
      elsif (busy_reg = '1') then
        if (cycle_cnt < ARRAY_ROWS + ARRAY_COLS - 1) then
          cycle_cnt <= cycle_cnt + 1;
        end if;
        if (cycle_cnt = ARRAY_ROWS + ARRAY_COLS - 1) then
          busy_reg <= '0';
          done_reg <= '1';
        end if;
      end if;
    end if;
  end process ctrl_fsm;

  -- Um unico processo cobrindo todos os (row,col) via lacos "for" (em vez de
  -- um processo por elemento via "generate" aninhado): garante um unico
  -- driver para o sinal composto "act_skew_regs" em qualquer ferramenta de
  -- simulacao (ver nota sobre "several sources" acima da declaracao dos
  -- tipos). Semantica identica: cada linha `row` desliza seu valor de
  -- ativacao (entrando na coluna 0) uma coluna por ciclo.
  --
  -- IMPORTANTE: tambem zera no inicio de CADA novo start_i (nao so no
  -- clear_i explicito). O acelerador (neorv32_systolic_wb_accelerator)
  -- dispara varios start_i em sequencia -- um por linha do tile de
  -- ativacoes -- sem pulsar clear_i entre eles. Sem este reset por-start,
  -- valores remanescentes de uma linha anterior ficam "em transito" nas
  -- colunas 1..7 quando a proxima linha comeca, contaminando a soma parcial
  -- durante os primeiros ciclos (ate o pipeline "lavar" o valor antigo).
  -- Bug real encontrado via simulacao GHDL (neorv32_systolic_matmul_tb):
  -- a linha 0 sempre batia (pipe zerado so pelo reset global), as linhas
  -- seguintes divergiam cada vez mais.
  skew_proc: process(rstn_i, clk_i)
  begin
    if (rstn_i = '0') then
      for row in 0 to ARRAY_ROWS-1 loop
        for col in 0 to ARRAY_COLS-1 loop
          act_skew_regs(row)(col) <= (others => '0');
        end loop;
      end loop;
    elsif rising_edge(clk_i) then
      if (clear_i = '1') or (start_i = '1' and busy_reg = '0') then
        for row in 0 to ARRAY_ROWS-1 loop
          for col in 0 to ARRAY_COLS-1 loop
            act_skew_regs(row)(col) <= (others => '0');
          end loop;
        end loop;
      else
        for row in 0 to ARRAY_ROWS-1 loop
          act_skew_regs(row)(0) <= act_cols_i((row+1)*DATA_WIDTH-1 downto row*DATA_WIDTH);
          for col in 1 to ARRAY_COLS-1 loop
            act_skew_regs(row)(col) <= act_skew_regs(row)(col-1);
          end loop;
        end loop;
      end if;
    end if;
  end process skew_proc;

  gen_interconnect: for row in 0 to ARRAY_ROWS-1 generate
    gen_col: for col in 0 to ARRAY_COLS-1 generate

      a_in_pe(row)(col) <= act_skew_regs(row)(col);

      w_in_pe(row)(col) <= pe_weight_reg(row)(col) when weight_loaded = '1' else
                           (others => '0');

      gen_psum_top: if row = 0 generate
        p_in_pe(0)(col) <= (others => '0');
      end generate;

      gen_psum_mid: if row > 0 generate
        p_in_pe(row)(col) <= pe_p_out(row-1)(col);
      end generate;

      pe_inst: entity work.neorv32_systolic_pe
        generic map (
          DATA_WIDTH => DATA_WIDTH,
          ACC_WIDTH  => ACC_WIDTH
        )
        port map (
          clk_i   => clk_i,
          rstn_i  => rstn_i,
          en_i    => busy_reg,
          clr_i   => clear_i,
          a_in_i  => a_in_pe(row)(col),
          w_in_i  => w_in_pe(row)(col),
          p_in_i  => p_in_pe(row)(col),
          a_out_o => pe_a_out(row)(col),
          w_out_o => pe_w_out(row)(col),
          p_out_o => pe_p_out(row)(col)
        );

    end generate gen_col;
  end generate gen_interconnect;

  gen_output: for col in 0 to ARRAY_COLS-1 generate
    result_o((col+1)*ACC_WIDTH-1 downto col*ACC_WIDTH) <= pe_p_out(ARRAY_ROWS-1)(col);
  end generate gen_output;

end neorv32_systolic_array_rtl;
