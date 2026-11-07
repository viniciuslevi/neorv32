-- ================================================================================ --
-- Testbench: neorv32_systolic_wb_accelerator - registradores, matmul TxT e IRQ      --
-- -------------------------------------------------------------------------------- --
-- Autoverificavel, com o tamanho do array como generic (T = 8 ou 16):              --
--   1. INFO devolve T linhas x T colunas                                           --
--   2. Tres matmuls TxT seguidos com INT8 em toda a faixa [-128, 127], conferidos  --
--      contra a referencia calculada aqui (cada start exige a borda 0 -> 1)        --
--   3. Durante o calculo da operacao 2, os pesos da operacao 3 sao escritos em     --
--      WEIGHT: o resultado da operacao 2 nao pode mudar (o driver com DMA usa      --
--      isso para carregar o proximo tile de pesos durante o calculo)               --
--   4. A IRQ so sobe no fim da operacao inteira, nao depois da primeira linha      --
-- -------------------------------------------------------------------------------- --
-- Uso (GHDL): ver sim/run_accel_sim.sh, ou                                          --
--   ghdl -r --std=08 neorv32_systolic_wb_accelerator_tb -gT=16                     --
-- ================================================================================ --

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

entity neorv32_systolic_wb_accelerator_tb is
  generic (
    T : natural := 8
  );
end neorv32_systolic_wb_accelerator_tb;

architecture tb of neorv32_systolic_wb_accelerator_tb is

  constant CLK_PERIOD : time := 20 ns; -- 50 MHz

  signal clk  : std_ulogic := '0';
  signal rstn : std_ulogic := '0';
  signal irq  : std_ulogic;

  signal wb_adr   : std_ulogic_vector(31 downto 0) := (others => '0');
  signal wb_dat_o : std_ulogic_vector(31 downto 0) := (others => '0'); -- tb -> dut
  signal wb_dat_i : std_ulogic_vector(31 downto 0);                    -- dut -> tb
  signal wb_we    : std_ulogic := '0';
  signal wb_sel   : std_ulogic_vector(3 downto 0) := "1111";
  signal wb_stb   : std_ulogic := '0';
  signal wb_cyc   : std_ulogic := '0';
  signal wb_ack   : std_ulogic;
  signal wb_err   : std_ulogic;

  constant ADDR_CTRL   : natural := 16#000#;
  constant ADDR_STATUS : natural := 16#004#;
  constant ADDR_INFO   : natural := 16#00C#;
  constant ADDR_WEIGHT : natural := 16#100#;
  constant ADDR_ACT    : natural := 16#500#;
  constant ADDR_RESULT : natural := 16#900#;

  type mat_t  is array (0 to T-1, 0 to T-1) of integer;
  type mats_t is array (0 to 2) of mat_t;

  -- Gerador congruente linear: valores INT8 deterministicos, faixa inteira
  function make_mat(seed : natural) return mat_t is
    variable m : mat_t;
    variable s : unsigned(31 downto 0) := to_unsigned(seed, 32);
  begin
    for r in 0 to T-1 loop
      for c in 0 to T-1 loop
        s := resize(s * to_unsigned(1664525, 32) + to_unsigned(1013904223, 32), 32);
        m(r, c) := to_integer(unsigned(s(31 downto 24))) - 128;
      end loop;
    end loop;
    return m;
  end function;

  function pack4(m : mat_t; w : natural) return std_ulogic_vector is
    variable r : std_ulogic_vector(31 downto 0);
    variable i : natural;
  begin
    for b in 0 to 3 loop
      i := w * 4 + b;
      r(b*8+7 downto b*8) := std_ulogic_vector(to_signed(m(i / T, i mod T), 8));
    end loop;
    return r;
  end function;

begin

  clk <= not clk after CLK_PERIOD / 2;

  dut: entity work.neorv32_systolic_wb_accelerator
    generic map (
      ARRAY_SIZE => T
    )
    port map (
      clk_i    => clk,
      rstn_i   => rstn,
      irq_o    => irq,
      wb_adr_i => wb_adr,
      wb_dat_i => wb_dat_o,
      wb_dat_o => wb_dat_i,
      wb_we_i  => wb_we,
      wb_sel_i => wb_sel,
      wb_stb_i => wb_stb,
      wb_cyc_i => wb_cyc,
      wb_ack_o => wb_ack,
      wb_err_o => wb_err
    );

  stim: process
    variable rdata  : std_ulogic_vector(31 downto 0);
    variable errors : natural := 0;
    variable W, A   : mats_t;
    variable expect : integer;
    variable got    : integer;
    variable polls  : natural;

    procedure wb_write(addr : natural; data : std_ulogic_vector(31 downto 0)) is
    begin
      wait until rising_edge(clk);
      wb_adr <= std_ulogic_vector(to_unsigned(addr, 32));
      wb_dat_o <= data;
      wb_we  <= '1';
      wb_stb <= '1';
      wb_cyc <= '1';
      wait until rising_edge(clk) and wb_ack = '1';
      wb_we  <= '0';
      wb_stb <= '0';
      wb_cyc <= '0';
    end procedure;

    procedure wb_read(addr : natural; data : out std_ulogic_vector(31 downto 0)) is
    begin
      wait until rising_edge(clk);
      wb_adr <= std_ulogic_vector(to_unsigned(addr, 32));
      wb_we  <= '0';
      wb_stb <= '1';
      wb_cyc <= '1';
      wait until rising_edge(clk) and wb_ack = '1';
      data := wb_dat_i;
      wb_stb <= '0';
      wb_cyc <= '0';
    end procedure;

    procedure load_weights(m : mat_t) is
    begin
      for wi in 0 to T*T/4-1 loop
        wb_write(ADDR_WEIGHT + wi*4, pack4(m, wi));
      end loop;
    end procedure;

    procedure load_acts(m : mat_t) is
    begin
      for wi in 0 to T*T/4-1 loop
        wb_write(ADDR_ACT + wi*4, pack4(m, wi));
      end loop;
    end procedure;

    procedure start is
    begin
      wb_write(ADDR_CTRL, x"00000000");
      wb_write(ADDR_CTRL, x"00000001"); -- borda de subida de CTRL[0]
    end procedure;

    procedure wait_done is
    begin
      loop
        wb_read(ADDR_STATUS, rdata);
        exit when rdata(1) = '1';
      end loop;
    end procedure;

    procedure check_result(op : natural) is
    begin
      for m in 0 to T-1 loop
        for n in 0 to T-1 loop
          wb_read(ADDR_RESULT + (m*T+n)*4, rdata);
          got := to_integer(signed(rdata));
          expect := 0;
          for k in 0 to T-1 loop
            expect := expect + A(op)(m, k) * W(op)(k, n);
          end loop;
          if got /= expect then
            if errors < 10 then
              report "op " & integer'image(op) & " RESULT[" & integer'image(m) & "][" &
                     integer'image(n) & "] = " & integer'image(got) & ", esperado " &
                     integer'image(expect) severity error;
            end if;
            errors := errors + 1;
          end if;
        end loop;
      end loop;
    end procedure;

  begin
    for i in 0 to 2 loop
      W(i) := make_mat(11 + i * 7);
      A(i) := make_mat(101 + i * 13);
    end loop;

    rstn <= '0';
    wait for CLK_PERIOD * 5;
    rstn <= '1';
    wait for CLK_PERIOD * 2;

    -- 1. INFO
    wb_read(ADDR_INFO, rdata);
    if to_integer(unsigned(rdata(7 downto 0))) /= T or to_integer(unsigned(rdata(15 downto 8))) /= T then
      report "INFO = 0x" & to_hstring(rdata) & ", esperado " & integer'image(T) & "x" &
             integer'image(T) severity error;
      errors := errors + 1;
    end if;

    -- 2/4. Operacao 0: a IRQ nao pode subir antes do fim
    load_weights(W(0));
    load_acts(A(0));
    start;
    polls := 0;
    loop
      wb_read(ADDR_STATUS, rdata);
      exit when rdata(1) = '1';
      if irq = '1' then
        report "IRQ subiu com a operacao ainda em curso (STATUS=0x" & to_hstring(rdata) & ")"
          severity error;
        errors := errors + 1;
        exit;
      end if;
      polls := polls + 1;
    end loop;
    wait until rising_edge(clk);
    wait until rising_edge(clk);
    if irq /= '1' then
      report "IRQ nao subiu no fim da operacao" severity error;
      errors := errors + 1;
    end if;
    wb_write(ADDR_CTRL, x"00000004"); -- irq_clear
    wb_write(ADDR_CTRL, x"00000000");
    wait until rising_edge(clk);
    wait until rising_edge(clk);
    if irq /= '0' then
      report "IRQ nao limpou com CTRL[2]" severity error;
      errors := errors + 1;
    end if;
    check_result(0);

    -- 3. Operacao 1, com os pesos da operacao 2 escritos durante o calculo
    load_weights(W(1));
    load_acts(A(1));
    start;
    load_weights(W(2)); -- o array ja copiou W(1); WEIGHT agora e livre
    wb_read(ADDR_STATUS, rdata);
    if rdata(0) /= '1' then
      report "a operacao 1 terminou antes da escrita de W(2): o teste nao sobrepos nada"
        severity warning;
    end if;
    wait_done;
    check_result(1);

    -- Operacao 2: pesos ja carregados durante a operacao 1
    load_acts(A(2));
    start;
    wait_done;
    check_result(2);

    if errors = 0 then
      report "=== neorv32_systolic_wb_accelerator_tb (" & integer'image(T) & "x" & integer'image(T) &
             "): INFO, 3 x " & integer'image(T*T) & " resultados, IRQ e escrita de WEIGHT durante o calculo OK (PASS) ===";
    else
      report "=== neorv32_systolic_wb_accelerator_tb (" & integer'image(T) & "x" & integer'image(T) &
             "): " & integer'image(errors) & " ERROS (FAIL) ===" severity error;
    end if;
    std.env.stop;
  end process;

end tb;
