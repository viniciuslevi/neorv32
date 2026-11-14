-- ================================================================================ --
-- NEORV32 SoC - Top-level integrado DE2-115 (Fase 3/4 do TCC)                      --
-- -------------------------------------------------------------------------------- --
-- Integra: NEORV32 (RV32IMC) + XBUS -> gateway Wishbone -> {SDRAM, acelerador       --
-- sistolico 8x8 INT8}. Ver Metodologia 3.5 (hierarquia de modulos) e 3.10 (Fase 3:  --
-- "Integracao SDRAM + NEORV32").                                                   --
-- -------------------------------------------------------------------------------- --
-- Mapa de enderecos (barramento externo XBUS do NEORV32):                          --
--   0xA0000000 - 0xA7FFFFFF   SDRAM 128 MB (pesos, ativacoes, buffers)             --
--   0x90000000 - 0x9000FFFF   Acelerador sistolico (CTRL/STATUS/WEIGHT/ACT/RESULT) --
-- (0x80000000 e reservado ao DMEM interno do NEORV32 -- nao usado para XBUS)       --
-- -------------------------------------------------------------------------------- --
-- Clock: opera em 50 MHz direto do oscilador da placa (sem PLL) -- escolha         --
-- deliberada para evitar dependencia de IP ALTPLL gerada via Quartus GUI/          --
-- MegaWizard (nao disponivel via linha de comando neste ambiente de              --
-- desenvolvimento). O DRAM_CLK e derivado internamente no controlador SDRAM        --
-- (tcc_sdram_controller.vhd) com defasagem de meio ciclo. 50 MHz e             --
-- confortavelmente dentro da faixa do IS42S16320D-7 (ate ~143 MHz) e do NEORV32.   --
-- -------------------------------------------------------------------------------- --
-- Licensed under the BSD-3-Clause license                                          --
-- ================================================================================ --

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library neorv32;
use neorv32.neorv32_package.all;

entity neorv32_de2115_mnist_top is
  generic (
    CLOCK_FREQUENCY : natural := 50_000_000; -- clk_i, direto do oscilador da placa
    IMEM_SIZE       : natural := 32 * 1024;  -- 32 KB ROM interna (.text/.rodata)
    DMEM_SIZE       : natural := 16 * 1024   -- 16 KB RAM interna (.data/.bss/pilha)
  );
  port (
    -- Clock e reset --
    clk_i  : in std_ulogic;                     -- CLOCK_50 (PIN_Y2)
    key_n  : in std_ulogic_vector(1 downto 0);  -- KEY[0]=reset, KEY[1]=livre

    -- UART0 (RS-232, cabecalho da DE2-115) --
    uart0_txd_o : out std_ulogic;
    uart0_rxd_i : in  std_ulogic;

    -- LEDs de status --
    ledg_o : out std_ulogic_vector(7 downto 0);

    -- LCD 16x2 (HD44780). LCD_DATA e bidirecional na placa, mas so escrevemos
    -- (RW fixo em 0), entao e acionado como saida. Ver sw/.../lcd.c.
    lcd_data_o : out std_ulogic_vector(7 downto 0);
    lcd_rs_o   : out std_ulogic;
    lcd_rw_o   : out std_ulogic;
    lcd_en_o   : out std_ulogic;
    lcd_on_o   : out std_ulogic;
    lcd_blon_o : out std_ulogic;
    ledr_o : out std_ulogic_vector(7 downto 0);

    -- SDRAM (2x IS42S16320D em paralelo, 32 bits combinados) --
    dram_addr_o  : out std_ulogic_vector(12 downto 0);
    dram_ba_o    : out std_ulogic_vector(1 downto 0);
    dram_cas_n_o : out std_ulogic;
    dram_cke_o   : out std_ulogic;
    dram_clk_o   : out std_ulogic;
    dram_cs_n_o  : out std_ulogic;
    dram_dq_io   : inout std_logic_vector(31 downto 0);
    dram_dqm_o   : out std_ulogic_vector(3 downto 0);
    dram_ras_n_o : out std_ulogic;
    dram_we_n_o  : out std_ulogic
  );
end neorv32_de2115_mnist_top;

architecture neorv32_de2115_mnist_top_rtl of neorv32_de2115_mnist_top is

  signal rstn_sync : std_ulogic;
  signal rst_meta  : std_ulogic;

  -- XBUS (mestre, saindo do neorv32_top)
  signal xbus_adr    : std_ulogic_vector(31 downto 0);
  signal xbus_dat_o  : std_ulogic_vector(31 downto 0);  -- CPU -> perifericos
  signal xbus_dat_i  : std_ulogic_vector(31 downto 0);  -- perifericos -> CPU
  signal xbus_we     : std_ulogic;
  signal xbus_sel    : std_ulogic_vector(3 downto 0);
  signal xbus_stb    : std_ulogic;
  signal xbus_cyc    : std_ulogic;
  signal xbus_ack    : std_ulogic;
  signal xbus_err    : std_ulogic;
  signal xbus_cti    : std_ulogic_vector(2 downto 0);
  signal xbus_tag    : std_ulogic_vector(2 downto 0);

  -- Wishbone: SDRAM
  signal sdram_adr, sdram_dat_o, sdram_dat_i : std_ulogic_vector(31 downto 0);
  signal sdram_we, sdram_stb, sdram_cyc, sdram_ack, sdram_err : std_ulogic;
  signal sdram_sel : std_ulogic_vector(3 downto 0);

  -- Wishbone: acelerador sistolico
  signal accel_adr, accel_dat_o, accel_dat_i : std_ulogic_vector(31 downto 0);
  signal accel_we, accel_stb, accel_cyc, accel_ack, accel_err : std_ulogic;
  signal accel_sel : std_ulogic_vector(3 downto 0);
  signal accel_irq : std_ulogic;

  signal con_gpio_out : std_ulogic_vector(31 downto 0);
  signal con_gpio_in  : std_ulogic_vector(31 downto 0);

  signal sdram_pll_locked : std_ulogic;
  signal sdram_clk_pll_out : std_logic;
  signal sdram_rstn       : std_ulogic;

begin

  -- Mantem o controlador SDRAM em reset ate o PLL travar -- sem isso, a FSM
  -- podia comecar a sequencia de inicializacao do chip com DRAM_CLK ainda
  -- instavel/nao alternando, corrompendo tudo dali pra frente independente
  -- da defasagem configurada (foi exatamente o que se observou: mudar a
  -- fase nao alterava o resultado, sempre 0xFF uniforme).
  sdram_rstn <= rstn_sync and sdram_pll_locked;

  -- Clock defasado para DRAM_CLK (ALTPLL, gerado via qmegawiz -silent --
  -- ver sdram_clk_pll_core.vhd/.qip). Substitui o inversor combinacional
  -- puro (not clk_i) que causava corrupcao de dados em hardware real.
  sdram_clk_pll_inst: entity work.sdram_clk_pll_core
  port map (
    areset => not rstn_sync, -- areset do ALTPLL e ativo-alto
    inclk0 => clk_i,
    c0     => sdram_clk_pll_out,
    locked => sdram_pll_locked
  );

  -- DRAM_CLK vem do PLL (defasagem de -10000 ps = 180 graus a 50 MHz, validada em
  -- hardware; 0 ps desloca todo acesso em uma palavra), nao de um inversor combinacional.
  -- O inversor puro (not clk_i) deixava a fase real no pino a merce do atraso de
  -- roteamento generico do FPGA, sem rede de clock dedicada -- justamente a
  -- condicao que produz captura marginal nas linhas de dado.
  dram_clk_o <= std_ulogic(sdram_clk_pll_out);

  -- Sincronizador de reset (KEY[0] ativo-baixo, 2 flip-flops) ----------------------
  sync_rst: process(clk_i)
  begin
    if rising_edge(clk_i) then
      rst_meta  <= key_n(0);
      rstn_sync <= rst_meta;
    end if;
  end process;

  -- NEORV32 -------------------------------------------------------------------------
  neorv32_top_inst: neorv32_top
  generic map (
    CLOCK_FREQUENCY   => CLOCK_FREQUENCY,
    BOOT_MODE_SELECT  => 0,      -- boot via bootloader interno (upload de firmware via UART0)
    RISCV_ISA_C       => true,
    RISCV_ISA_M       => true,
    RISCV_ISA_Zicntr  => true,   -- contadores de ciclo/tempo (usados no benchmark da Fase 4)
    IMEM_EN           => true,
    IMEM_SIZE         => IMEM_SIZE,
    DMEM_EN           => true,
    DMEM_SIZE         => DMEM_SIZE,
    IO_GPIO_NUM       => 32,     -- 8 LEDs + 8 dados do LCD + RS + EN
    IO_CLINT_EN       => true,
    IO_UART0_EN       => true,
    IO_UART0_RX_FIFO  => 64,      -- absorve rajadas do upload do bootloader (padrao de 1 byte causa overflow)
    XBUS_EN           => true,   -- habilita barramento externo (SDRAM + acelerador)
    XBUS_TIMEOUT      => 2048,
    XBUS_REGSTAGE_EN  => false
  )
  port map (
    clk_i       => clk_i,
    rstn_i      => rstn_sync,
    gpio_o      => con_gpio_out,
    gpio_i      => con_gpio_in,
    uart0_txd_o => uart0_txd_o,
    uart0_rxd_i => uart0_rxd_i,
    xbus_adr_o  => xbus_adr,
    xbus_dat_o  => xbus_dat_o,
    xbus_cti_o  => xbus_cti,
    xbus_tag_o  => xbus_tag,
    xbus_we_o   => xbus_we,
    xbus_sel_o  => xbus_sel,
    xbus_stb_o  => xbus_stb,
    xbus_cyc_o  => xbus_cyc,
    xbus_dat_i  => xbus_dat_i,
    xbus_ack_i  => xbus_ack,
    xbus_err_i  => xbus_err
  );

  -- Gateway XBUS -> Wishbone (decodificacao de endereco) -----------------------------
  gateway_inst: entity work.neorv32_xbus_wb_gateway
  port map (
    clk_i  => clk_i,
    rstn_i => rstn_sync,

    xbus_adr_i => xbus_adr,
    xbus_dat_i => xbus_dat_o,  -- dado vindo da CPU (saida do neorv32_top)
    xbus_dat_o => xbus_dat_i,  -- dado indo para a CPU (entrada do neorv32_top)
    xbus_we_i  => xbus_we,
    xbus_sel_i => xbus_sel,
    xbus_stb_i => xbus_stb,
    xbus_cyc_i => xbus_cyc,
    xbus_ack_o => xbus_ack,
    xbus_err_o => xbus_err,

    sdram_adr_o => sdram_adr,
    sdram_dat_o => sdram_dat_o,
    sdram_dat_i => sdram_dat_i,
    sdram_we_o  => sdram_we,
    sdram_sel_o => sdram_sel,
    sdram_stb_o => sdram_stb,
    sdram_cyc_o => sdram_cyc,
    sdram_ack_i => sdram_ack,
    sdram_err_i => sdram_err,

    accel_adr_o => accel_adr,
    accel_dat_o => accel_dat_o,
    accel_dat_i => accel_dat_i,
    accel_we_o  => accel_we,
    accel_sel_o => accel_sel,
    accel_stb_o => accel_stb,
    accel_cyc_o => accel_cyc,
    accel_ack_i => accel_ack,
    accel_err_i => accel_err
  );

  -- Controlador SDRAM -----------------------------------------------------------------
  -- Voltou aos defaults da entidade: a combinacao com T_RP=3/RCD=3/RC=6/MRD=4
  -- travou a placa (pior que o "tudo 0xff" anterior, que ao menos completava)
  -- -- revertido ate isolar se aquilo era um bug real ou uma gravacao JTAG
  -- ruim (o adaptador USB do Blaster pode ter o mesmo tipo de instabilidade
  -- ja visto no CH340 da UART nesta bancada).
  sdram_inst: entity work.neorv32_sdram_controller
  port map (
    clk_i  => clk_i,
    rstn_i => sdram_rstn, -- segurado ate o PLL do DRAM_CLK travar

    wb_adr_i => sdram_adr,
    wb_dat_i => sdram_dat_o,
    wb_dat_o => sdram_dat_i,
    wb_we_i  => sdram_we,
    wb_sel_i => sdram_sel,
    wb_stb_i => sdram_stb,
    wb_cyc_i => sdram_cyc,
    wb_ack_o => sdram_ack,
    wb_err_o => sdram_err,

    dram_addr_o  => dram_addr_o,
    dram_ba_o    => dram_ba_o,
    dram_cas_n_o => dram_cas_n_o,
    dram_cke_o   => dram_cke_o,
    dram_cs_n_o  => dram_cs_n_o,
    dram_dq_io   => dram_dq_io,
    dram_dqm_o   => dram_dqm_o,
    dram_ras_n_o => dram_ras_n_o,
    dram_we_n_o  => dram_we_n_o
  );

  -- Acelerador sistolico 8x8 INT8 (Wishbone) -------------------------------------------
  accel_inst: entity work.neorv32_systolic_wb_accelerator
  port map (
    clk_i    => clk_i,
    rstn_i   => rstn_sync,
    irq_o    => accel_irq,  -- nao conectado a um controlador de interrupcao externo
                             -- (firmware da Fase 3/4 usa polling de STATUS; IRQ fica
                             -- disponivel para trabalho futuro via PLIC/FIRQ)
    wb_adr_i => accel_adr,
    wb_dat_i => accel_dat_o,
    wb_dat_o => accel_dat_i,
    wb_we_i  => accel_we,
    wb_sel_i => accel_sel,
    wb_stb_i => accel_stb,
    wb_cyc_i => accel_cyc,
    wb_ack_o => accel_ack,
    wb_err_o => accel_err
  );

  -- LEDs de status ------------------------------------------------------------------
  -- LEDG[7:0]: 8 LSBs do GPIO de proposito geral do NEORV32 (uso livre do firmware)
  -- LEDR[0]: heartbeat de reset liberado | LEDR[1]: acelerador ocupado
  -- KEY[1] chega ao software em gpio_i(0). O botao da DE2-115 e ativo-baixo;
  -- invertemos aqui para que '1' signifique "pressionado" no firmware.
  con_gpio_in <= (0 => not key_n(1), others => '0');

  ledg_o <= con_gpio_out(7 downto 0);

  -- LCD: dados em gpio[15:8], RS em gpio[16], EN em gpio[17]. RW fixo em 0
  -- (nunca lemos o busy flag; o driver usa os tempos do datasheet), e
  -- alimentacao/backlight sempre ligados.
  lcd_data_o <= con_gpio_out(15 downto 8);
  lcd_rs_o   <= con_gpio_out(16);
  lcd_en_o   <= con_gpio_out(17);
  lcd_rw_o   <= '0';
  lcd_on_o   <= '1';
  lcd_blon_o <= '1';
  ledr_o(0) <= rstn_sync;
  ledr_o(1) <= accel_irq;
  ledr_o(2) <= sdram_pll_locked; -- diagnostico: PLL do DRAM_CLK travou?
  ledr_o(7 downto 3) <= (others => '0');

end neorv32_de2115_mnist_top_rtl;
