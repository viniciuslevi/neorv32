-- ================================================================================ --
-- NEORV32 - Teste Standalone do Array Sistolico na DE2-115                          --
-- -------------------------------------------------------------------------------- --
-- Teste visual sem CPU: carrega dados hardcoded, dispara via botao, mostra         --
-- resultados nos LEDs. Nao precisa de software nem UART.                            --
-- -------------------------------------------------------------------------------- --
-- Hardware DE2-115 utilizado:                                                       --
--   KEY[0] (PIN_M23) - Reset ativo-baixo                                           --
--   KEY[1] (PIN_M21) - Dispara computacao (borda de descida = pressiona)           --
--   LEDG[7:0]        - Resultado: bits [7:0] de result[0] (pinos confirmados)      --
--   LEDR[7:0]        - Status: [0]=busy_latch, [1]=done, [2]=idle                  --
-- -------------------------------------------------------------------------------- --
-- Cenario de teste:                                                                 --
--   Pesos (por linha):  [01, 02, 03, 04, 05, 06, 07, 08]                          --
--   Ativacoes (por col): [01, 01, 01, 01, 01, 01, 01, 01]                         --
--   Resultado esperado por coluna: 1+2+3+4+5+6+7+8 = 36 = 0x24                    --
--   LEDG deve mostrar 0x24 = "00100100" (LEDG[2] e LEDG[5] acesos)                --
-- ================================================================================ --

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity neorv32_systolic_standalone_test is
	port (
		clk_i  : in  std_ulogic;
		key_n  : in  std_ulogic_vector(1 downto 0);
		ledg_o : out std_ulogic_vector(7 downto 0);
		ledr_o : out std_ulogic_vector(7 downto 0)
	);
end neorv32_systolic_standalone_test;

architecture rtl of neorv32_systolic_standalone_test is

	constant ARRAY_ROWS : natural := 8;
	constant ARRAY_COLS : natural := 8;
	constant DATA_WIDTH : natural := 8;
	constant ACC_WIDTH  : natural := 32;

	signal array_start : std_ulogic;
	signal array_clear : std_ulogic;
	signal array_done  : std_ulogic;
	signal array_busy  : std_ulogic;

	signal weight_rows : std_ulogic_vector(ARRAY_ROWS * DATA_WIDTH - 1 downto 0);
	signal weight_tile : std_ulogic_vector(ARRAY_ROWS * ARRAY_COLS * DATA_WIDTH - 1 downto 0);
	signal act_cols    : std_ulogic_vector(ARRAY_COLS * DATA_WIDTH - 1 downto 0);
	signal result_data : std_ulogic_vector(ARRAY_COLS * ACC_WIDTH - 1 downto 0);

	type test_state_t is (T_IDLE, T_START, T_WAIT, T_DONE);
	signal test_state : test_state_t;

	signal key1_meta : std_ulogic;
	signal key1_sync : std_ulogic;
	signal key1_prev : std_ulogic;
	signal start_btn : std_ulogic;

	signal busy_latch : std_ulogic;
	signal result_latch : std_ulogic_vector(7 downto 0);

begin

	sync_btn : process(clk_i)
	begin
		if rising_edge(clk_i) then
			key1_meta <= key_n(1);
			key1_sync <= key1_meta;
			key1_prev <= key1_sync;
		end if;
	end process;

	start_btn <= key1_prev and not key1_sync;

	weight_rows <= x"08_07_06_05_04_03_02_01";
	act_cols    <= x"01_01_01_01_01_01_01_01";

	-- Broadcast each row's weight byte across all columns of the flattened
	-- weight-stationary tile expected by neorv32_systolic_array's weight_i,
	-- reproducing the old per-row broadcast so the expected test result
	-- (sum 1+2+...+8 = 0x24 per column) is unchanged.
	gen_weight_bcast : for row in 0 to ARRAY_ROWS - 1 generate
		gen_weight_col : for col in 0 to ARRAY_COLS - 1 generate
			weight_tile((row * ARRAY_COLS + col + 1) * DATA_WIDTH - 1 downto (row * ARRAY_COLS + col) * DATA_WIDTH) <=
				weight_rows((row + 1) * DATA_WIDTH - 1 downto row * DATA_WIDTH);
		end generate gen_weight_col;
	end generate gen_weight_bcast;

	test_fsm : process(clk_i)
	begin
		if rising_edge(clk_i) then
			if key_n(0) = '0' then
				test_state   <= T_IDLE;
				array_start  <= '0';
				array_clear  <= '1';
				busy_latch   <= '0';
				result_latch <= (others => '0');
			else
				array_clear <= '0';
				array_start <= '0';

				case test_state is
					when T_IDLE =>
						if start_btn = '1' then
							test_state <= T_START;
							busy_latch <= '1';
						end if;

					when T_START =>
						array_start <= '1';
						test_state  <= T_WAIT;

					when T_WAIT =>
						if array_done = '1' then
							result_latch <= result_data(7 downto 0);
							busy_latch   <= '0';
							test_state   <= T_DONE;
						end if;

					when T_DONE =>
						test_state <= T_IDLE;

				end case;
			end if;
		end if;
	end process;

	systolic_array_inst : entity work.neorv32_systolic_array
		generic map (
			ARRAY_ROWS => ARRAY_ROWS,
			ARRAY_COLS => ARRAY_COLS,
			DATA_WIDTH  => DATA_WIDTH,
			ACC_WIDTH   => ACC_WIDTH
		)
		port map (
			clk_i         => clk_i,
			rstn_i        => key_n(0),
			start_i       => array_start,
			clear_i       => array_clear,
			act_cols_i    => act_cols,
			weight_i      => weight_tile,
			done_o        => array_done,
			busy_o        => array_busy,
			result_o      => result_data
		);

	-- LEDG: resultado travado (pinos confirmados da DE2-115)
	-- Esperado: 0x24 = LEDG[2] e LEDG[5] acesos
	ledg_o <= result_latch;

	-- LEDR: status
	-- LEDR[0] = busy_latch (visivel, fica aceso durante toda a computacao)
	-- LEDR[1] = done (fica aceso apos conclusao)
	-- LEDR[2] = idle (aceso quando aguardando)
	ledr_o(0) <= busy_latch;
	ledr_o(1) <= array_done;
	ledr_o(2) <= '1' when test_state = T_IDLE and key_n(0) = '1' else '0';
	ledr_o(7 downto 3) <= (others => '0');

end rtl;
