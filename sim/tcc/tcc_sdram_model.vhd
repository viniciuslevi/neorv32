-- ================================================================================ --
-- Modelo comportamental de SDR SDRAM para simulacao (NAO sintetizavel)             --
-- -------------------------------------------------------------------------------- --
-- Decodifica o mesmo conjunto de comandos JEDEC usado por tcc_sdram_controller --
-- (cs_n,ras_n,cas_n,we_n) e implementa ACTIVE/READ/WRITE/PRECHARGE/REFRESH/MRS de   --
-- forma funcional (sem modelar tempos de acesso do datasheet -- o objetivo aqui e   --
-- validar a SEQUENCIA de comandos e a integridade dos dados, nao timing).           --
-- -------------------------------------------------------------------------------- --
-- Limitacao deliberada: para manter a simulacao leve, o array de armazenamento     --
-- cobre apenas ROW(3 downto 0) (16 linhas) x todas as colunas x todos os bancos     --
-- (16 * 1024 * 4 = 65536 words). Os testes devem usar apenas linhas 0-15 -- ver     --
-- tcc_sdram_controller_tb.vhd.                                                 --
-- -------------------------------------------------------------------------------- --
-- Licensed under the BSD-3-Clause license                                          --
-- ================================================================================ --

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tcc_sdram_model is
  port (
    dram_addr_i  : in    std_ulogic_vector(12 downto 0);
    dram_ba_i    : in    std_ulogic_vector(1 downto 0);
    dram_cas_n_i : in    std_ulogic;
    dram_cke_i   : in    std_ulogic;
    dram_clk_i   : in    std_ulogic;
    dram_cs_n_i  : in    std_ulogic;
    dram_dq_io   : inout std_logic_vector(31 downto 0);
    dram_dqm_i   : in    std_ulogic_vector(3 downto 0);
    dram_ras_n_i : in    std_ulogic;
    dram_we_n_i  : in    std_ulogic
  );
end tcc_sdram_model;

architecture behavioral of tcc_sdram_model is

  constant CAS_LATENCY : natural := 2;

  type mem_t is array (0 to 65535) of std_logic_vector(31 downto 0);
  -- "mem" e acessada (leitura e escrita) apenas dentro de cmd_proc, entao vive
  -- como variavel local desse processo (evita "shared variable" de tipo nao
  -- protegido, que o VHDL-2008 estrito trata como extensao de vendor).

  type bank_row_t is array (0 to 3) of std_ulogic_vector(12 downto 0);
  signal open_row   : bank_row_t;
  signal row_active : std_ulogic_vector(3 downto 0) := (others => '0');

  signal col_latched : std_ulogic_vector(9 downto 0);
  signal bank_latched : std_ulogic_vector(1 downto 0);
  signal dq_out : std_logic_vector(31 downto 0);
  signal dq_out_en : std_ulogic := '0';

  -- Indice de simulacao: usa apenas os 4 bits menos significativos da linha
  function model_index(bank : std_ulogic_vector(1 downto 0);
                        row  : std_ulogic_vector(12 downto 0);
                        col  : std_ulogic_vector(9 downto 0)) return natural is
    variable idx : natural;
  begin
    idx := to_integer(unsigned(bank)) * 16384 +
           to_integer(unsigned(row(3 downto 0))) * 1024 +
           to_integer(unsigned(col));
    return idx;
  end function;

begin

  dram_dq_io <= dq_out when dq_out_en = '1' else (others => 'Z');

  cmd_proc: process(dram_clk_i)
    variable cmd : std_ulogic_vector(3 downto 0);
    variable idx : natural;
    variable read_pipe : natural := 0;
    variable mem : mem_t := (others => (others => '0'));
  begin
    if rising_edge(dram_clk_i) then
      dq_out_en <= '0';

      cmd := dram_cs_n_i & dram_ras_n_i & dram_cas_n_i & dram_we_n_i;

      case cmd is
        when "0011" => -- ACTIVE
          open_row(to_integer(unsigned(dram_ba_i))) <= dram_addr_i;
          row_active(to_integer(unsigned(dram_ba_i))) <= '1';

        when "0010" => -- PRECHARGE
          if dram_addr_i(10) = '1' then
            row_active <= (others => '0'); -- precharge all
          else
            row_active(to_integer(unsigned(dram_ba_i))) <= '0';
          end if;

        when "0100" => -- WRITE
          assert row_active(to_integer(unsigned(dram_ba_i))) = '1'
            report "tcc_sdram_model: WRITE sem ACTIVE previo no banco" severity error;
          idx := model_index(dram_ba_i, open_row(to_integer(unsigned(dram_ba_i))), dram_addr_i(9 downto 0));
          for b in 0 to 3 loop
            if dram_dqm_i(b) = '0' then
              mem(idx)((b+1)*8-1 downto b*8) := std_logic_vector(dram_dq_io((b+1)*8-1 downto b*8));
            end if;
          end loop;

        when "0101" => -- READ
          assert row_active(to_integer(unsigned(dram_ba_i))) = '1'
            report "tcc_sdram_model: READ sem ACTIVE previo no banco" severity error;
          idx := model_index(dram_ba_i, open_row(to_integer(unsigned(dram_ba_i))), dram_addr_i(9 downto 0));
          -- agenda a saida do dado CAS_LATENCY ciclos a frente (processo separado)
          col_latched  <= dram_addr_i(9 downto 0);
          bank_latched <= dram_ba_i;
          dq_out       <= mem(idx);
          read_pipe    := CAS_LATENCY;

        when "0001" => -- AUTO REFRESH
          null; -- funcional: nao precisa fazer nada no modelo comportamental

        when "0000" => -- MRS
          null;

        when others =>
          null;
      end case;

      -- pipeline simples de CAS latency para READ (modelo funcional, nao cycle-exact
      -- para outros comandos que nao sejam READ)
      if read_pipe > 0 then
        read_pipe := read_pipe - 1;
        if read_pipe = 0 then
          dq_out_en <= '1';
        end if;
      end if;

    end if;
  end process cmd_proc;

end behavioral;
