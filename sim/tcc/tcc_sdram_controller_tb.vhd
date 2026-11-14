-- ================================================================================ --
-- Testbench: tcc_sdram_controller - Escrita/leitura + integridade sob refresh  --
-- -------------------------------------------------------------------------------- --
-- Nivel 1/2 de verificacao (Metodologia 3.8). Conecta o controlador ao modelo       --
-- comportamental (tcc_sdram_model.vhd) e, como mestre Wishbone classico,        --
-- escreve valores conhecidos em enderecos de bancos/linhas distintos (forcando     --
-- ACTIVE/PRECHARGE reais), le de volta e confere. Os generics de temporizacao sao   --
-- reduzidos para acelerar a simulacao (nao afeta a logica, apenas os contadores).  --
-- -------------------------------------------------------------------------------- --
-- Uso (GHDL): ghdl -a --std=08 rtl/tcc/tcc_sdram_controller.vhd \              --
--               sim/tcc/tcc_sdram_model.vhd sim/tcc/tcc_sdram_controller_tb.vhd    --
--             ghdl -e --std=08 tcc_sdram_controller_tb                         --
--             ghdl -r --std=08 tcc_sdram_controller_tb                         --
-- ================================================================================ --

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

entity tcc_sdram_controller_tb is
end tcc_sdram_controller_tb;

architecture tb of tcc_sdram_controller_tb is

  constant CLK_PERIOD : time := 20 ns; -- 50 MHz

  signal clk  : std_ulogic := '0';
  signal rstn : std_ulogic := '0';

  signal wb_adr   : std_ulogic_vector(31 downto 0) := (others => '0');
  signal wb_dat_o : std_ulogic_vector(31 downto 0) := (others => '0');
  signal wb_dat_i : std_ulogic_vector(31 downto 0);
  signal wb_we    : std_ulogic := '0';
  signal wb_sel   : std_ulogic_vector(3 downto 0) := "1111";
  signal wb_stb   : std_ulogic := '0';
  signal wb_cyc   : std_ulogic := '0';
  signal wb_ack   : std_ulogic;
  signal wb_err   : std_ulogic;

  signal dram_addr  : std_ulogic_vector(12 downto 0);
  signal dram_ba    : std_ulogic_vector(1 downto 0);
  signal dram_cas_n : std_ulogic;
  signal dram_cke   : std_ulogic;
  signal dram_clk   : std_ulogic;
  signal dram_cs_n  : std_ulogic;
  signal dram_dq    : std_logic_vector(31 downto 0);
  signal dram_dqm   : std_ulogic_vector(3 downto 0);
  signal dram_ras_n : std_ulogic;
  signal dram_we_n  : std_ulogic;

  procedure wb_write(
    signal   clk_i : in  std_ulogic;
    signal   adr_o : out std_ulogic_vector(31 downto 0);
    signal   dat_o : out std_ulogic_vector(31 downto 0);
    signal   we_o  : out std_ulogic;
    signal   stb_o : out std_ulogic;
    signal   cyc_o : out std_ulogic;
    signal   ack_i : in  std_ulogic;
    constant addr  : in  std_ulogic_vector(31 downto 0);
    constant data  : in  std_ulogic_vector(31 downto 0)
  ) is
  begin
    wait until rising_edge(clk_i);
    adr_o <= addr;
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
    signal   clk_i : in  std_ulogic;
    signal   adr_o : out std_ulogic_vector(31 downto 0);
    signal   we_o  : out std_ulogic;
    signal   stb_o : out std_ulogic;
    signal   cyc_o : out std_ulogic;
    signal   ack_i : in  std_ulogic;
    signal   dat_i : in  std_ulogic_vector(31 downto 0);
    constant addr  : in  std_ulogic_vector(31 downto 0);
    variable data  : out std_ulogic_vector(31 downto 0)
  ) is
  begin
    wait until rising_edge(clk_i);
    adr_o <= addr;
    we_o  <= '0';
    stb_o <= '1';
    cyc_o <= '1';
    wait until rising_edge(clk_i) and ack_i = '1';
    data := dat_i;
    stb_o <= '0';
    cyc_o <= '0';
  end procedure;

  -- Mestre no estilo do XBUS do NEORV32 (Wishbone pipelined): stb fica alto por
  -- UM ciclo e cyc continua alto ate o ack. O endereco e o dado mudam logo apos
  -- o stb, para provar que o controlador registrou o pedido no ciclo do stb.
  -- Sem ack em TMO ciclos o pedido conta como perdido (no SoC, isso e o
  -- XBUS_TIMEOUT virando access fault).
  constant TMO : natural := 64;

  procedure wb_access_p(
    signal   clk_i : in  std_ulogic;
    signal   adr_o : out std_ulogic_vector(31 downto 0);
    signal   dat_o : out std_ulogic_vector(31 downto 0);
    signal   we_o  : out std_ulogic;
    signal   stb_o : out std_ulogic;
    signal   cyc_o : out std_ulogic;
    signal   ack_i : in  std_ulogic;
    signal   dat_i : in  std_ulogic_vector(31 downto 0);
    constant write : in  boolean;
    constant addr  : in  std_ulogic_vector(31 downto 0);
    constant wdata : in  std_ulogic_vector(31 downto 0);
    variable rdata : out std_ulogic_vector(31 downto 0);
    variable lost  : out boolean
  ) is
    variable n : natural;
  begin
    wait until rising_edge(clk_i);
    adr_o <= addr;
    dat_o <= wdata;
    if write then we_o <= '1'; else we_o <= '0'; end if;
    stb_o <= '1';
    cyc_o <= '1';
    wait until rising_edge(clk_i);
    stb_o <= '0';
    adr_o <= x"DEADBEE0"; -- lixo: o controlador ja deve ter registrado o pedido
    dat_o <= x"0BADF00D";
    n := 0;
    lost := false;
    while ack_i /= '1' loop
      if n = TMO then
        lost := true;
        exit;
      end if;
      wait until rising_edge(clk_i);
      n := n + 1;
    end loop;
    rdata := dat_i;
    cyc_o <= '0';
    we_o  <= '0';
  end procedure;

begin

  clk <= not clk after CLK_PERIOD / 2;

  -- dram_clk_o deixou de ser gerado pelo controlador (agora vem de um PLL
  -- com defasagem controlada no top-level real, ver neorv32_sdram_clk_pll.vhd
  -- -- a corrupcao de dados vista em hardware nao existe no simulador com
  -- modelo ideal, entao um inversor simples aqui continua valido pro teste).
  dram_clk <= not clk;

  dut: entity work.tcc_sdram_controller
    generic map (
      INIT_WAIT_CYCLES   => 50,
      T_RP_CYCLES        => 1,
      T_RCD_CYCLES       => 1,
      T_RC_CYCLES        => 3,
      T_MRD_CYCLES       => 2,
      CAS_LATENCY        => 2,
      INIT_REFRESH_COUNT => 2,
      REFRESH_INTERVAL   => 60
    )
    port map (
      clk_i  => clk,
      rstn_i => rstn,

      wb_adr_i => wb_adr,
      wb_dat_i => wb_dat_o,
      wb_dat_o => wb_dat_i,
      wb_we_i  => wb_we,
      wb_sel_i => wb_sel,
      wb_stb_i => wb_stb,
      wb_cyc_i => wb_cyc,
      wb_ack_o => wb_ack,
      wb_err_o => wb_err,

      dram_addr_o  => dram_addr,
      dram_ba_o    => dram_ba,
      dram_cas_n_o => dram_cas_n,
      dram_cke_o   => dram_cke,
      dram_cs_n_o  => dram_cs_n,
      dram_dq_io   => dram_dq,
      dram_dqm_o   => dram_dqm,
      dram_ras_n_o => dram_ras_n,
      dram_we_n_o  => dram_we_n
    );

  model: entity work.tcc_sdram_model
    port map (
      dram_addr_i  => dram_addr,
      dram_ba_i    => dram_ba,
      dram_cas_n_i => dram_cas_n,
      dram_cke_i   => dram_cke,
      dram_clk_i   => dram_clk,
      dram_cs_n_i  => dram_cs_n,
      dram_dq_io   => dram_dq,
      dram_dqm_i   => dram_dqm,
      dram_ras_n_i => dram_ras_n,
      dram_we_n_i  => dram_we_n
    );

  stim: process
    variable rdata  : std_ulogic_vector(31 downto 0);
    variable errors : natural := 0;

    -- Enderecos de word (25 bits: banco[24:23] & linha[22:10] & coluna[9:0]) --
    -- linhas restritas a 0-15 por limitacao do modelo comportamental (ver
    -- tcc_sdram_model.vhd). Bancos e colunas variam livremente.
    type addr_array_t is array (natural range <>) of natural;
    constant TEST_WORD_ADDRS : addr_array_t := (
      16#0000000#,             -- banco 0, linha 0, coluna 0
      16#0000005#,             -- banco 0, linha 0, coluna 5
      (1 * 8192 + 0) * 1024,   -- banco 1, linha 0, coluna 0
      (2 * 8192 + 3) * 1024,   -- banco 2, linha 3, coluna 0
      (0 * 8192 + 7) * 1024 + 100 -- banco 0, linha 7, coluna 100
    );
    variable byte_addr : std_ulogic_vector(31 downto 0);
    variable expected  : std_ulogic_vector(31 downto 0);
    constant P2_N      : natural := 200;
    variable lost      : boolean;
    variable p2_lost   : natural := 0;
  begin
    rstn <= '0';
    wait for CLK_PERIOD * 5;
    rstn <= '1';

    -- aguarda o controlador sair da inicializacao (S_IDLE) -- folga generosa
    wait for CLK_PERIOD * 200;

    -- Escreve um padrao distinto por endereco
    for i in TEST_WORD_ADDRS'range loop
      byte_addr := std_ulogic_vector(to_unsigned(TEST_WORD_ADDRS(i) * 4, 32));
      expected  := std_ulogic_vector(to_unsigned(16#25A50000# + i, 32));
      wb_write(clk, wb_adr, wb_dat_o, wb_we, wb_stb, wb_cyc, wb_ack, byte_addr, expected);
    end loop;

    -- Forca alguns ciclos de refresh automatico antes de ler de volta
    wait for CLK_PERIOD * 150;

    -- Le de volta e confere
    for i in TEST_WORD_ADDRS'range loop
      byte_addr := std_ulogic_vector(to_unsigned(TEST_WORD_ADDRS(i) * 4, 32));
      expected  := std_ulogic_vector(to_unsigned(16#25A50000# + i, 32));
      wb_read(clk, wb_adr, wb_we, wb_stb, wb_cyc, wb_ack, wb_dat_i, byte_addr, rdata);
      if rdata /= expected then
        report "MISMATCH addr=" & integer'image(TEST_WORD_ADDRS(i)) &
               " got=0x" & to_hstring(rdata) & " expected=0x" & to_hstring(expected)
               severity error;
        errors := errors + 1;
      end if;
    end loop;

    -- Fase 2: mestre pipelined (stb de 1 ciclo), varios acessos em sequencia
    -- com intervalos variados, de modo que parte dos stb caia durante um
    -- AUTO REFRESH. Escreve P2_N palavras e le de volta.
    report "fase 2: mestre com stb de 1 ciclo (estilo XBUS)";
    for i in 0 to P2_N-1 loop
      byte_addr := std_ulogic_vector(to_unsigned(((i mod 16) * 1024 + (i / 16) * 3) * 4, 32));
      expected  := std_ulogic_vector(to_unsigned(16#5A000000# + i * 7919, 32));
      wb_access_p(clk, wb_adr, wb_dat_o, wb_we, wb_stb, wb_cyc, wb_ack, wb_dat_i,
                  true, byte_addr, expected, rdata, lost);
      if lost then p2_lost := p2_lost + 1; end if;
      for g in 1 to (i mod 5) loop
        wait until rising_edge(clk);
      end loop;
    end loop;
    for i in 0 to P2_N-1 loop
      byte_addr := std_ulogic_vector(to_unsigned(((i mod 16) * 1024 + (i / 16) * 3) * 4, 32));
      expected  := std_ulogic_vector(to_unsigned(16#5A000000# + i * 7919, 32));
      wb_access_p(clk, wb_adr, wb_dat_o, wb_we, wb_stb, wb_cyc, wb_ack, wb_dat_i,
                  false, byte_addr, x"00000000", rdata, lost);
      if lost then
        p2_lost := p2_lost + 1;
      elsif rdata /= expected then
        report "fase 2 MISMATCH i=" & integer'image(i) & " got=0x" & to_hstring(rdata) &
               " expected=0x" & to_hstring(expected) severity error;
        errors := errors + 1;
      end if;
      for g in 1 to (i mod 3) loop
        wait until rising_edge(clk);
      end loop;
    end loop;
    report "fase 2: " & integer'image(2 * P2_N) & " acessos, " & integer'image(p2_lost) &
           " sem ack (perdidos)";
    if p2_lost /= 0 then
      report "fase 2: pedidos com stb de 1 ciclo foram perdidos" severity error;
      errors := errors + p2_lost;
    end if;

    if errors = 0 then
      report "=== tcc_sdram_controller_tb: TODOS OS ENDERECOS OK, DADOS INTEGROS APOS REFRESH (PASS) ===";
    else
      report "=== tcc_sdram_controller_tb: " & integer'image(errors) & " ERROS (FAIL) ===" severity error;
    end if;

    std.env.stop;
  end process;

end tb;
