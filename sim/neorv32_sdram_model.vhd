-- ================================================================================ --
-- Modelo comportamental de SDR SDRAM para simulacao (NAO sintetizavel)             --
-- -------------------------------------------------------------------------------- --
-- Decodifica o mesmo conjunto de comandos JEDEC usado por neorv32_sdram_controller --
-- (cs_n,ras_n,cas_n,we_n) e implementa ACTIVE/READ/WRITE/PRECHARGE/REFRESH/MRS de   --
-- forma funcional (sem modelar tempos de acesso do datasheet -- o objetivo aqui e   --
-- validar a SEQUENCIA de comandos e a integridade dos dados, nao timing).           --
-- -------------------------------------------------------------------------------- --
-- Limitacao deliberada: para manter a simulacao leve, o array de armazenamento     --
-- cobre apenas ROW(ROW_BITS-1 downto 0) x todas as colunas x todos os bancos. Com   --
-- o padrao ROW_BITS = 4 sao 16 linhas por banco (64 KB contiguos a partir do       --
-- endereco 0); linhas acima disso se repetem. Os testes devem ficar dentro disso.  --
-- ROW_BITS = 11 cobre os 8 MB do banco 0 (pesos, buffers e tiles da inferencia).  --
-- Cada word ocupa um integer (4 bytes), nao um std_logic_vector (32 bytes no GHDL). --
--                                                                                  --
-- INIT_FILE0/1: arquivos binarios carregados no tempo 0 a partir do byte           --
-- INIT_OFFS0/1 (multiplo de 4) do banco 0, no lugar do upload pela UART da placa   --
-- (ver sim/run_infer_sim.sh). "" = nao carrega.                                    --
-- -------------------------------------------------------------------------------- --
-- Licensed under the BSD-3-Clause license                                          --
-- ================================================================================ --

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity neorv32_sdram_model is
  generic (
    ROW_BITS   : natural range 1 to 13 := 4;
    INIT_FILE0 : string  := "";
    INIT_OFFS0 : natural := 0;
    INIT_FILE1 : string  := "";
    INIT_OFFS1 : natural := 0
  );
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
end neorv32_sdram_model;

architecture behavioral of neorv32_sdram_model is

  constant CAS_LATENCY : natural := 2;

  constant WORDS_PER_BANK : natural := (2 ** ROW_BITS) * 1024;
  type mem_t is array (0 to 4 * WORDS_PER_BANK - 1) of integer;
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

  -- Indice de simulacao: usa apenas os ROW_BITS bits menos significativos da linha
  function model_index(bank : std_ulogic_vector(1 downto 0);
                        row  : std_ulogic_vector(12 downto 0);
                        col  : std_ulogic_vector(9 downto 0)) return natural is
    variable idx : natural;
  begin
    idx := to_integer(unsigned(bank)) * WORDS_PER_BANK +
           to_integer(unsigned(row(ROW_BITS-1 downto 0))) * 1024 +
           to_integer(unsigned(col));
    return idx;
  end function;

  function to_word(v : integer) return std_logic_vector is
  begin
    return std_logic_vector(to_signed(v, 32));
  end function;

  function to_int(w : std_logic_vector(31 downto 0)) return integer is
  begin
    return to_integer(signed(w));
  end function;

  type byte_file_t is file of character;

begin

  dram_dq_io <= dq_out when dq_out_en = '1' else (others => 'Z');

  cmd_proc: process(dram_clk_i)
    variable cmd : std_ulogic_vector(3 downto 0);
    variable idx : natural;
    variable read_pipe : natural := 0;
    variable mem : mem_t := (others => 0);
    variable loaded : boolean := false;
    variable word_v : std_logic_vector(31 downto 0);

    -- Copia um arquivo binario para mem a partir do byte offs (little-endian)
    procedure load(name : string; offs : natural) is
      file f      : byte_file_t;
      variable st : file_open_status;
      variable c  : character;
      variable n  : natural := 0;
      variable w  : std_logic_vector(31 downto 0) := (others => '0');
    begin
      file_open(st, f, name, read_mode);
      assert st = open_ok report "neorv32_sdram_model: nao abriu " & name severity failure;
      while not endfile(f) loop
        read(f, c);
        w(((n mod 4) + 1) * 8 - 1 downto (n mod 4) * 8) :=
          std_logic_vector(to_unsigned(character'pos(c), 8));
        if (n mod 4) = 3 then
          mem(offs / 4 + n / 4) := to_int(w);
          w := (others => '0');
        end if;
        n := n + 1;
      end loop;
      if (n mod 4) /= 0 then
        mem(offs / 4 + n / 4) := to_int(w);
      end if;
      file_close(f);
      report "neorv32_sdram_model: " & name & " carregado (" & integer'image(n) &
             " bytes a partir de " & integer'image(offs) & ")";
    end procedure;
  begin
    if not loaded then
      loaded := true;
      if INIT_FILE0 /= "" then load(INIT_FILE0, INIT_OFFS0); end if;
      if INIT_FILE1 /= "" then load(INIT_FILE1, INIT_OFFS1); end if;
    end if;
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
            report "neorv32_sdram_model: WRITE sem ACTIVE previo no banco" severity error;
          idx := model_index(dram_ba_i, open_row(to_integer(unsigned(dram_ba_i))), dram_addr_i(9 downto 0));
          word_v := to_word(mem(idx));
          for b in 0 to 3 loop
            if dram_dqm_i(b) = '0' then
              word_v((b+1)*8-1 downto b*8) := std_logic_vector(dram_dq_io((b+1)*8-1 downto b*8));
            end if;
          end loop;
          mem(idx) := to_int(word_v);

        when "0101" => -- READ
          assert row_active(to_integer(unsigned(dram_ba_i))) = '1'
            report "neorv32_sdram_model: READ sem ACTIVE previo no banco" severity error;
          idx := model_index(dram_ba_i, open_row(to_integer(unsigned(dram_ba_i))), dram_addr_i(9 downto 0));
          -- agenda a saida do dado CAS_LATENCY ciclos a frente (processo separado)
          col_latched  <= dram_addr_i(9 downto 0);
          bank_latched <= dram_ba_i;
          dq_out       <= to_word(mem(idx));
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
