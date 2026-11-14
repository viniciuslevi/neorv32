-- ================================================================================ --
-- NEORV32 Testbench with Systolic Array Accelerator on XBUS                        --
-- -------------------------------------------------------------------------------- --
-- Based on neorv32_tb with the accelerator mapped at 0x80000000 (XBUS DEV_6).       --
-- Software running on NEORV32 can access the accelerator as external memory.        --
-- ================================================================================ --

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;

library neorv32;
use neorv32.neorv32_package.all;

entity tcc_systolic_tb is
  generic (
    CLOCK_FREQUENCY   : natural                        := 100_000_000;
    DUAL_CORE_EN      : boolean                        := false;
    BOOT_MODE_SELECT  : natural range 0 to 2           := 2;
    RISCV_ISA_C       : boolean                        := true;
    RISCV_ISA_M       : boolean                        := true;
    RISCV_ISA_U       : boolean                        := false;
    IMEM_EN           : boolean                        := true;
    IMEM_BASE         : std_ulogic_vector(31 downto 0) := x"00000000";
    IMEM_SIZE         : natural                        := 32*1024;
    DMEM_EN           : boolean                        := true;
    DMEM_BASE         : std_ulogic_vector(31 downto 0) := x"80000000";
    DMEM_SIZE         : natural                        := 8*1024;
    ICACHE_EN         : boolean                        := false;
    DCACHE_EN         : boolean                        := false;
    CACHE_BLOCK_SIZE  : natural range 4 to 1024        := 32;
    CACHE_BURSTS_EN   : boolean                        := false;
    ACCEL_BASE        : std_ulogic_vector(31 downto 0) := x"90000000";
    ACCEL_SIZE        : natural                        := 4096
  );
end tcc_systolic_tb;

architecture tb_rtl of tcc_systolic_tb is

  signal clk_en, clk_gen, rst_gen : std_ulogic;
  constant f_period_c : time := (1 sec) / CLOCK_FREQUENCY;

  signal uart0_txd, uart0_ctsn, uart1_txd, uart1_ctsn : std_ulogic;
  signal gpio : std_ulogic_vector(31 downto 0);

  signal xbus_core_req : xbus_req_t;
  signal xbus_core_rsp : xbus_rsp_t;
  signal xbus_accel_req : xbus_req_t;
  signal xbus_accel_rsp : xbus_rsp_t;

  signal accel_irq : std_ulogic;

begin

  rst_gen <= '0', '1' after 30*(f_period_c/2);
  clk_en  <= '0', '1' after 60*(f_period_c/2);
  clk_gen <= (not clk_gen) and clk_en after (f_period_c/2);

  neorv32_top_inst: neorv32_top
  generic map (
    CLOCK_FREQUENCY     => CLOCK_FREQUENCY,
    DUAL_CORE_EN        => DUAL_CORE_EN,
    BOOT_MODE_SELECT    => BOOT_MODE_SELECT,
    RISCV_ISA_C         => RISCV_ISA_C,
    RISCV_ISA_M         => RISCV_ISA_M,
    RISCV_ISA_U         => RISCV_ISA_U,
    CPU_FAST_MUL_EN     => true,
    CPU_FAST_SHIFT_EN   => true,
    IMEM_EN             => IMEM_EN,
    IMEM_BASE           => IMEM_BASE,
    IMEM_SIZE           => IMEM_SIZE,
    DMEM_EN             => DMEM_EN,
    DMEM_BASE           => DMEM_BASE,
    DMEM_SIZE           => DMEM_SIZE,
    ICACHE_EN           => ICACHE_EN,
    DCACHE_EN           => DCACHE_EN,
    CACHE_BLOCK_SIZE    => CACHE_BLOCK_SIZE,
    CACHE_BURSTS_EN     => CACHE_BURSTS_EN,
    XBUS_EN             => true,
    XBUS_TIMEOUT        => 4096,
    XBUS_REGSTAGE_EN    => false,
    IO_GPIO_NUM         => 32,
    IO_UART0_EN         => true,
    IO_UART0_RX_FIFO    => 32,
    IO_UART0_TX_FIFO    => 32,
    IO_CFS_EN           => false
  )
  port map (
    clk_i          => clk_gen,
    rstn_i         => rst_gen,
    rstn_ocd_o     => open,
    rstn_wdt_o     => open,
    trace_cpu0_o   => open,
    trace_cpu1_o   => open,
    jtag_tck_i     => '0',
    jtag_tdi_i     => '0',
    jtag_tdo_o     => open,
    jtag_tms_i     => '0',
    xbus_adr_o     => xbus_core_req.addr,
    xbus_dat_o     => xbus_core_req.data,
    xbus_cti_o     => xbus_core_req.cti,
    xbus_tag_o     => xbus_core_req.tag,
    xbus_we_o      => xbus_core_req.we,
    xbus_sel_o     => xbus_core_req.sel,
    xbus_stb_o     => xbus_core_req.stb,
    xbus_cyc_o     => xbus_core_req.cyc,
    xbus_dat_i     => xbus_core_rsp.data,
    xbus_ack_i     => xbus_core_rsp.ack,
    xbus_err_i     => xbus_core_rsp.err,
    gpio_o         => gpio,
    gpio_i         => gpio,
    uart0_txd_o    => uart0_txd,
    uart0_rxd_i    => '1',
    uart0_rtsn_o   => uart0_ctsn,
    uart0_ctsn_i   => '0',
    cfs_in_i       => (others => '0'),
    cfs_out_o      => open,
    pwm_o          => open,
    neoled_o       => open,
    mtime_time_o   => open,
    irq_msi_i      => '0',
    irq_mti_i      => '0',
    irq_mei_i      => accel_irq
  );

  xbus_interconnect: entity work.xbus_gateway
  generic map (
    DEV_0_EN => false, DEV_0_SIZE => 0,              DEV_0_BASE => (others => '0'),
    DEV_1_EN => false, DEV_1_SIZE => 0,              DEV_1_BASE => (others => '0'),
    DEV_2_EN => false, DEV_2_SIZE => 0,              DEV_2_BASE => (others => '0'),
    DEV_3_EN => false, DEV_3_SIZE => 0,              DEV_3_BASE => (others => '0'),
    DEV_4_EN => false, DEV_4_SIZE => 0,              DEV_4_BASE => (others => '0'),
    DEV_5_EN => false, DEV_5_SIZE => 0,              DEV_5_BASE => (others => '0'),
    DEV_6_EN => true,  DEV_6_SIZE => ACCEL_SIZE,     DEV_6_BASE => ACCEL_BASE,
    DEV_7_EN => false, DEV_7_SIZE => 0,              DEV_7_BASE => (others => '0')
  )
  port map (
    host_req_i  => xbus_core_req,
    host_rsp_o  => xbus_core_rsp,
    dev_0_req_o => open,               dev_0_rsp_i => xbus_rsp_terminate_c,
    dev_1_req_o => open,               dev_1_rsp_i => xbus_rsp_terminate_c,
    dev_2_req_o => open,               dev_2_rsp_i => xbus_rsp_terminate_c,
    dev_3_req_o => open,               dev_3_rsp_i => xbus_rsp_terminate_c,
    dev_4_req_o => open,               dev_4_rsp_i => xbus_rsp_terminate_c,
    dev_5_req_o => open,               dev_5_rsp_i => xbus_rsp_terminate_c,
    dev_6_req_o => xbus_accel_req,     dev_6_rsp_i => xbus_accel_rsp,
    dev_7_req_o => open,               dev_7_rsp_i => xbus_rsp_terminate_c
  );

  accelerator_inst: entity work.tcc_systolic_wb_accelerator
    port map (
      clk_i    => clk_gen,
      rstn_i   => rst_gen,
      irq_o    => accel_irq,
      wb_adr_i => xbus_accel_req.addr,
      wb_dat_i => xbus_accel_req.data,
      wb_dat_o => xbus_accel_rsp.data,
      wb_we_i  => xbus_accel_req.we,
      wb_sel_i => xbus_accel_req.sel,
      wb_stb_i => xbus_accel_req.stb,
      wb_cyc_i => xbus_accel_req.cyc,
      wb_ack_o => xbus_accel_rsp.ack,
      wb_err_o => xbus_accel_rsp.err
    );

  sim_rx_uart0: entity work.sim_uart_rx
  generic map (
    NAME => "tb.uart0_rx",
    FCLK => real(CLOCK_FREQUENCY),
    BAUD => real(19200)
  )
  port map (
    clk => clk_gen,
    rxd => uart0_txd
  );

end tb_rtl;
