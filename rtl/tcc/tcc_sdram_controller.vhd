-- ================================================================================ --
-- NEORV32 SoC - SDR SDRAM Controller (Wishbone Interface) - DE2-115                --
-- -------------------------------------------------------------------------------- --
-- Controlador simples (single-word, close-page) para os 2x ISSI IS42S16320D-7      --
-- da placa DE2-115 (Terasic), ligados em paralelo formando um barramento de dados   --
-- combinado de 32 bits (16 bits por chip) -> 32M x 32bit = 128 MB endereaveis.      --
-- -------------------------------------------------------------------------------- --
-- Escopo do TCC (Fase 3 - Metodologia 3.4/3.5): substitui a IP SDRAM do Quartus    --
-- (nao disponivel via linha de comando neste ambiente) por uma RTL propria,        --
-- documentada e sintetizavel em Cyclone IV E, seguindo o fluxo padrao de comandos  --
-- SDR SDRAM (JEDEC). Politica de pagina fechada (close-page): cada acesso faz      --
-- ACTIVE -> READ/WRITE -> PRECHARGE. Mais simples e robusta que open-page (sem     --
-- necessidade de rastrear linha aberta por banco), ao custo de desempenho -- ver   --
-- limitacao 3.11 da metodologia ("SDRAM e lenta, CPU como intermediaria, sem DMA   --
-- no escopo base"). Otimizacao para open-page fica como trabalho futuro.          --
-- -------------------------------------------------------------------------------- --
-- Geometria por chip (IS42S16320D-7, 512 Mbit = 32M x 16 bit):                     --
--   4 bancos x 8192 linhas x 1024 colunas x 16 bits                                --
--   BA[1:0] = banco | ADDR[12:0] = linha (ACTIVE) | ADDR[9:0] = coluna (READ/WRITE)--
-- Os dois chips compartilham CLK/CKE/CS#/RAS#/CAS#/WE#/ADDR/BA (mesmo endereco     --
-- logico), diferindo apenas em DRAM_DQ[15:0] (chip 0) e DRAM_DQ[31:16] (chip 1).   --
-- -------------------------------------------------------------------------------- --
-- Temporizacao (clock do sistema = 50 MHz, periodo 20 ns; margens generosas frente --
-- ao datasheet -7, que suporta ate ~133-143 MHz):                                  --
--   tRP  (precharge)         >= 15 ns  -> 1 ciclo de espera apos PRECHARGE         --
--   tRCD (RAS->CAS)          >= 15 ns  -> 1 ciclo de espera apos ACTIVE            --
--   tRC  (row cycle, init)   >= 60 ns  -> 3 ciclos apos AUTO REFRESH               --
--   CL   (CAS latency)       = 2 ciclos (programado no Mode Register)              --
--   tMRD (mode register set) = 2 ciclos                                            --
--   Power-up                 >= 100 us antes do primeiro comando (JEDEC)           --
--   Refresh                  8192 linhas / 64 ms  => 1 refresh a cada ~390 ciclos  --
-- -------------------------------------------------------------------------------- --
-- DRAM_CLK NAO e gerado neste arquivo -- ver neorv32_sdram_clk_pll.vhd. A          --
-- tentativa inicial (inversor combinacional puro, not clk_i) causou corrupcao de   --
-- dados em hardware real (fase sujeita ao atraso de roteamento generico do FPGA,   --
-- nao capturada pela simulacao com modelo ideal de SDRAM); substituida por PLL     --
-- com defasagem controlada.                                                        --
-- -------------------------------------------------------------------------------- --
-- Licensed under the BSD-3-Clause license                                          --
-- ================================================================================ --

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library neorv32;
use neorv32.neorv32_package.all;

entity tcc_sdram_controller is
  generic (
    -- Contadores de temporizacao (em ciclos de clk_i @ 50 MHz); ver cabecalho.
    INIT_WAIT_CYCLES  : natural := 5000;  -- >= 100 us @ 50 MHz
    T_RP_CYCLES        : natural := 1;     -- tRP
    T_RCD_CYCLES        : natural := 1;    -- tRCD
    T_RC_CYCLES         : natural := 3;    -- tRC (usado apos AUTO REFRESH)
    T_WR_CYCLES         : natural := 2;    -- tWR (write recovery, comando WRITE -> PRECHARGE)
    T_MRD_CYCLES        : natural := 2;    -- tMRD
    CAS_LATENCY         : natural := 2;    -- ciclos entre READ e dado valido
    INIT_REFRESH_COUNT  : natural := 8;    -- auto-refreshes minimos no boot (JEDEC exige >=2)
    REFRESH_INTERVAL    : natural := 380   -- ciclos entre AUTO REFRESH (margem sobre 390.6)
  );
  port (
    clk_i   : in  std_ulogic;
    rstn_i  : in  std_ulogic;

    -- Barramento Wishbone classico (escravo) -- janela de 128 MB (25 bits de word)
    wb_adr_i : in  std_ulogic_vector(31 downto 0);
    wb_dat_i : in  std_ulogic_vector(31 downto 0);
    wb_dat_o : out std_ulogic_vector(31 downto 0);
    wb_we_i  : in  std_ulogic;
    wb_sel_i : in  std_ulogic_vector(3 downto 0);
    wb_stb_i : in  std_ulogic;
    wb_cyc_i : in  std_ulogic;
    wb_ack_o : out std_ulogic;
    wb_err_o : out std_ulogic;

    -- Pinos fisicos do SDRAM (DE2-115)
    -- NOTA: dram_clk_o NAO e gerado aqui -- ver neorv32_sdram_clk_pll.vhd. Um
    -- inversor combinacional (not clk_i) alimentando o pino direto causou
    -- corrupcao de dados em hardware real (fase de clock sujeita ao atraso
    -- de roteamento generico do FPGA, nao capturada pela simulacao GHDL
    -- com modelo ideal de SDRAM). Agora vem de um PLL com defasagem
    -- controlada, instanciado a parte no top-level.
    dram_addr_o  : out std_ulogic_vector(12 downto 0);
    dram_ba_o    : out std_ulogic_vector(1 downto 0);
    dram_cas_n_o : out std_ulogic;
    dram_cke_o   : out std_ulogic;
    dram_cs_n_o  : out std_ulogic;
    dram_dq_io   : inout std_logic_vector(31 downto 0);
    dram_dqm_o   : out std_ulogic_vector(3 downto 0);
    dram_ras_n_o : out std_ulogic;
    dram_we_n_o  : out std_ulogic
  );
end tcc_sdram_controller;

architecture neorv32_sdram_controller_rtl of tcc_sdram_controller is

  -- Comandos SDR SDRAM: (cs_n, ras_n, cas_n, we_n)
  subtype cmd_t is std_ulogic_vector(3 downto 0);
  constant CMD_MRS       : cmd_t := "0000";
  constant CMD_REFRESH   : cmd_t := "0001";
  constant CMD_PRECHARGE : cmd_t := "0010";
  constant CMD_ACTIVE    : cmd_t := "0011";
  constant CMD_WRITE     : cmd_t := "0100";
  constant CMD_READ      : cmd_t := "0101";
  constant CMD_NOP       : cmd_t := "0111";
  constant CMD_DESELECT  : cmd_t := "1000"; -- cs_n='1' (demais nao importam)

  signal cmd_reg : cmd_t;

  type fsm_t is (
    S_INIT_WAIT, S_INIT_PRECHARGE, S_INIT_PRECHARGE_WAIT,
    S_INIT_REFRESH, S_INIT_REFRESH_WAIT,
    S_INIT_MRS, S_INIT_MRS_WAIT,
    S_IDLE,
    S_REFRESH, S_REFRESH_WAIT,
    S_ACTIVE, S_ACTIVE_WAIT,
    S_READ, S_READ_WAIT,
    S_WRITE, S_WRITE_PULSE, S_WRITE_RECOVER,
    S_PRECHARGE, S_PRECHARGE_WAIT,
    S_DONE
  );
  signal state : fsm_t;

  signal wait_cnt    : natural range 0 to INIT_WAIT_CYCLES;
  signal refresh_cnt : natural range 0 to INIT_REFRESH_COUNT;
  signal refresh_due_cnt : natural range 0 to REFRESH_INTERVAL;
  signal refresh_pending  : std_ulogic;

  -- Requisicao Wishbone latched
  signal req_addr  : std_ulogic_vector(24 downto 0);  -- endereco de word (bank+row+col)
  signal req_wdata : std_ulogic_vector(31 downto 0);
  signal req_sel   : std_ulogic_vector(3 downto 0);
  signal req_we    : std_ulogic;
  signal req_pending : std_ulogic;

  signal bank_sel : std_ulogic_vector(1 downto 0);
  signal row_sel  : std_ulogic_vector(12 downto 0);
  signal col_sel  : std_ulogic_vector(9 downto 0);

  signal dq_out_en : std_ulogic;  -- '1' enquanto o controlador dirige dram_dq_io
  signal dq_out_reg : std_ulogic_vector(31 downto 0);
  signal rdata_reg  : std_ulogic_vector(31 downto 0);

  signal ack_reg : std_ulogic;

begin

  -- Decompoe o endereco de word Wishbone (25 bits) em banco/linha/coluna.
  -- wb_adr_i e byte-endereco; bits (26 downto 2) formam o endereco de word de 32 bits.
  -- req_addr e REGISTRADO em latch_req (nao derivado de wb_adr_i combinacionalmente):
  -- a FSM leva varios ciclos entre ACTIVE e READ/WRITE, e wb_adr_i pode mudar nesse
  -- intervalo -- o que fazia ACTIVE capturar a linha de um endereco e READ/WRITE a
  -- coluna de outro, gravando/lendo na palavra vizinha.
  bank_sel <= req_addr(24 downto 23);
  row_sel  <= req_addr(22 downto 10);
  col_sel  <= req_addr(9 downto 0);

  dram_cs_n_o  <= cmd_reg(3);
  dram_ras_n_o <= cmd_reg(2);
  dram_cas_n_o <= cmd_reg(1);
  dram_we_n_o  <= cmd_reg(0);

  dram_dq_io <= std_logic_vector(dq_out_reg) when dq_out_en = '1' else (others => 'Z');

  wb_err_o <= '0';  -- controlador nunca sinaliza erro de barramento

  -- Latch da requisicao Wishbone: aceita um novo pedido apenas em S_IDLE
  latch_req: process(rstn_i, clk_i)
  begin
    if (rstn_i = '0') then
      req_pending <= '0';
      req_addr    <= (others => '0');
      req_wdata   <= (others => '0');
      req_sel     <= (others => '0');
      req_we      <= '0';
    elsif rising_edge(clk_i) then
      if (state = S_IDLE and wb_cyc_i = '1' and wb_stb_i = '1' and req_pending = '0') then
        req_pending <= '1';
        req_addr    <= wb_adr_i(26 downto 2);
        req_wdata   <= wb_dat_i;
        req_sel     <= wb_sel_i;
        req_we      <= wb_we_i;
      elsif (state = S_DONE) then
        req_pending <= '0';
      end if;
    end if;
  end process latch_req;

  -- Contador de refresh periodico (livre, incrementa sempre; FSM zera ao atender)
  refresh_timer: process(rstn_i, clk_i)
  begin
    if (rstn_i = '0') then
      refresh_due_cnt <= 0;
      refresh_pending <= '0';
    elsif rising_edge(clk_i) then
      if (state = S_REFRESH) then
        refresh_due_cnt <= 0;
        refresh_pending <= '0';
      elsif (refresh_due_cnt = REFRESH_INTERVAL) then
        refresh_pending <= '1';
      else
        refresh_due_cnt <= refresh_due_cnt + 1;
      end if;
    end if;
  end process refresh_timer;

  main_fsm: process(rstn_i, clk_i)
  begin
    if (rstn_i = '0') then
      state       <= S_INIT_WAIT;
      cmd_reg     <= CMD_DESELECT;
      dram_cke_o  <= '0';
      dram_addr_o <= (others => '0');
      dram_ba_o   <= (others => '0');
      dram_dqm_o  <= (others => '1');
      dq_out_en   <= '0';
      dq_out_reg  <= (others => '0');
      rdata_reg   <= (others => '0');
      wait_cnt    <= 0;
      refresh_cnt <= 0;
      ack_reg     <= '0';

    elsif rising_edge(clk_i) then
      cmd_reg    <= CMD_NOP;  -- default: NOP a cada ciclo, estados abaixo sobrescrevem
      dram_dqm_o <= (others => '1');
      dq_out_en  <= '0';
      ack_reg    <= '0';

      case state is

        ---------------------------------------------------------------
        -- Inicializacao (JEDEC power-up sequence)
        ---------------------------------------------------------------
        when S_INIT_WAIT =>
          dram_cke_o <= '1';
          if (wait_cnt < INIT_WAIT_CYCLES) then
            wait_cnt <= wait_cnt + 1;
          else
            wait_cnt <= 0;
            state    <= S_INIT_PRECHARGE;
          end if;

        when S_INIT_PRECHARGE =>
          cmd_reg          <= CMD_PRECHARGE;
          dram_addr_o(10)  <= '1';  -- precharge all banks
          wait_cnt         <= 0;
          state            <= S_INIT_PRECHARGE_WAIT;

        when S_INIT_PRECHARGE_WAIT =>
          if (wait_cnt < T_RP_CYCLES) then
            wait_cnt <= wait_cnt + 1;
          else
            wait_cnt    <= 0;
            refresh_cnt <= 0;
            state       <= S_INIT_REFRESH;
          end if;

        when S_INIT_REFRESH =>
          cmd_reg  <= CMD_REFRESH;
          wait_cnt <= 0;
          state    <= S_INIT_REFRESH_WAIT;

        when S_INIT_REFRESH_WAIT =>
          if (wait_cnt < T_RC_CYCLES) then
            wait_cnt <= wait_cnt + 1;
          else
            wait_cnt <= 0;
            if (refresh_cnt < INIT_REFRESH_COUNT - 1) then
              refresh_cnt <= refresh_cnt + 1;
              state       <= S_INIT_REFRESH;
            else
              state <= S_INIT_MRS;
            end if;
          end if;

        when S_INIT_MRS =>
          cmd_reg <= CMD_MRS;
          dram_ba_o <= "00";
          -- Mode register: [12:10]=rsv(000) [9]=WBL(0) [8:7]=rsv/test(00)
          --                [6:4]=CAS latency(010=2) [3]=burst type(0=seq) [2:0]=burst length(000=1)
          dram_addr_o(12 downto 10) <= "000";
          dram_addr_o(9)            <= '0';
          dram_addr_o(8 downto 7)   <= "00";
          dram_addr_o(6 downto 4)   <= "010";
          dram_addr_o(3)            <= '0';
          dram_addr_o(2 downto 0)   <= "000";
          wait_cnt <= 0;
          state    <= S_INIT_MRS_WAIT;

        when S_INIT_MRS_WAIT =>
          if (wait_cnt < T_MRD_CYCLES) then
            wait_cnt <= wait_cnt + 1;
          else
            state <= S_IDLE;
          end if;

        ---------------------------------------------------------------
        -- Operacao normal
        ---------------------------------------------------------------
        when S_IDLE =>
          wait_cnt <= 0;
          if (refresh_pending = '1') then
            state <= S_REFRESH;
          elsif (req_pending = '1') then
            state <= S_ACTIVE;
          end if;

        when S_REFRESH =>
          cmd_reg  <= CMD_REFRESH;
          wait_cnt <= 0;
          state    <= S_REFRESH_WAIT;

        when S_REFRESH_WAIT =>
          if (wait_cnt < T_RC_CYCLES) then
            wait_cnt <= wait_cnt + 1;
          else
            state <= S_IDLE;
          end if;

        when S_ACTIVE =>
          cmd_reg     <= CMD_ACTIVE;
          dram_ba_o   <= bank_sel;
          dram_addr_o <= row_sel;
          wait_cnt    <= 0;
          state       <= S_ACTIVE_WAIT;

        when S_ACTIVE_WAIT =>
          if (wait_cnt < T_RCD_CYCLES) then
            wait_cnt <= wait_cnt + 1;
          else
            wait_cnt <= 0;
            if (req_we = '1') then
              state <= S_WRITE;
            else
              state <= S_READ;
            end if;
          end if;

        when S_WRITE =>
          cmd_reg                    <= CMD_WRITE;
          dram_ba_o                  <= bank_sel;
          dram_addr_o(9 downto 0)    <= col_sel;
          dram_addr_o(10)            <= '0';  -- sem auto-precharge
          dram_addr_o(12 downto 11)  <= "00";
          dq_out_en                  <= '1';
          dq_out_reg                 <= req_wdata;
          -- DQM ativo-baixo: '0' habilita a escrita do byte (segue wb_sel_i)
          dram_dqm_o(0) <= not req_sel(0);
          dram_dqm_o(1) <= not req_sel(1);
          dram_dqm_o(2) <= not req_sel(2);
          dram_dqm_o(3) <= not req_sel(3);
          state <= S_WRITE_PULSE;

        when S_WRITE_PULSE =>
          -- mantem DQ estavel por 1 ciclo apos o comando WRITE (tDS/tDH)
          dq_out_en   <= '1';
          dq_out_reg  <= req_wdata;
          dram_dqm_o(0) <= not req_sel(0);
          dram_dqm_o(1) <= not req_sel(1);
          dram_dqm_o(2) <= not req_sel(2);
          dram_dqm_o(3) <= not req_sel(3);
          wait_cnt <= 0;
          state <= S_WRITE_RECOVER;

        when S_WRITE_RECOVER =>
          -- tWR: confirmado logicamente correto via GHDL (sdram_byte_tb ad-hoc,
          -- escritas byte-a-byte na mesma palavra preservam os outros lanes).
          -- A regressao "tudo 0xff" em hardware real persistiu mesmo com isso
          -- revertido, entao nao era a causa -- mantido ligado.
          if (wait_cnt < T_WR_CYCLES) then
            wait_cnt <= wait_cnt + 1;
          else
            wait_cnt <= 0;
            state    <= S_PRECHARGE;
          end if;

        when S_READ =>
          cmd_reg                   <= CMD_READ;
          dram_ba_o                 <= bank_sel;
          dram_addr_o(9 downto 0)   <= col_sel;
          dram_addr_o(10)           <= '0';  -- sem auto-precharge
          dram_addr_o(12 downto 11) <= "00";
          dram_dqm_o                <= (others => '0');  -- habilita saida do chip
          wait_cnt <= 0;
          state <= S_READ_WAIT;

        when S_READ_WAIT =>
          -- O dado do chip/modelo fica valido em dram_dq_io por apenas 1
          -- ciclo (burst length = 1). A captura precisa acontecer NESTE
          -- estado, no ciclo exato em que o contador atinge o alvo -- usar
          -- um estado S_READ_CAPTURE separado adiciona 1 ciclo de atraso
          -- (a transicao de estado ja consome 1 ciclo) e amostra
          -- dram_dq_io depois que ele ja voltou a alta impedancia. Bug real
          -- encontrado via simulacao GHDL (tcc_sdram_controller_tb).
          dram_dqm_o <= (others => '0');
          if (wait_cnt < CAS_LATENCY - 1) then
            wait_cnt <= wait_cnt + 1;
          else
            rdata_reg <= std_ulogic_vector(dram_dq_io);
            wait_cnt  <= 0;
            state     <= S_PRECHARGE;
          end if;

        when S_PRECHARGE =>
          cmd_reg         <= CMD_PRECHARGE;
          dram_ba_o       <= bank_sel;
          dram_addr_o(10) <= '0';  -- precharge somente o banco corrente
          wait_cnt        <= 0;
          state           <= S_PRECHARGE_WAIT;

        when S_PRECHARGE_WAIT =>
          if (wait_cnt < T_RP_CYCLES) then
            wait_cnt <= wait_cnt + 1;
          else
            ack_reg <= '1';
            state   <= S_DONE;
          end if;

        when S_DONE =>
          state <= S_IDLE;

      end case;
    end if;
  end process main_fsm;

  wb_dat_o <= rdata_reg;
  wb_ack_o <= ack_reg;

end neorv32_sdram_controller_rtl;
