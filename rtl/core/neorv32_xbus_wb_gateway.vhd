-- ================================================================================ --
-- NEORV32 SoC - XBUS to Wishbone-classic Address-Decoded Gateway                   --
-- -------------------------------------------------------------------------------- --
-- Ponte simples de 1 mestre (XBUS do NEORV32) para N escravos Wishbone classico,   --
-- decodificando pelo endereco. O XBUS do NEORV32 ja e eletricamente compativel     --
-- com Wishbone classico (adr/dat/we/sel/stb/cyc/ack/err), entao a ponte e apenas   --
-- um decodificador de endereco + mux de retorno (dat_o/ack_o/err_o).               --
-- -------------------------------------------------------------------------------- --
-- Mapa de memoria (Fase 3 - Metodologia 3.5, hierarquia de modulos):               --
--   0xA0000000 - 0xA7FFFFFF (128 MB)  SDRAM (neorv32_sdram_controller)             --
--   0x90000000 - 0x9000FFFF (64 KB)   Acelerador sistolico (neorv32_systolic_wb_*) --
-- Enderecos fora dessas janelas geram wb_err (acesso a regiao XBUS nao mapeada).   --
-- NOTA: 0x80000000 e reservado (DMEM interno do NEORV32, generico DMEM_BASE) --    --
-- por isso a janela SDRAM comeca em 0xA0000000 e nao em 0x80000000.                --
-- -------------------------------------------------------------------------------- --
-- Licensed under the BSD-3-Clause license                                          --
-- ================================================================================ --

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library neorv32;
use neorv32.neorv32_package.all;

entity neorv32_xbus_wb_gateway is
  generic (
    SDRAM_BASE_ADDR : std_ulogic_vector(31 downto 0) := x"A0000000";
    SDRAM_SIZE      : natural := 128 * 1024 * 1024;  -- 128 MB
    ACCEL_BASE_ADDR : std_ulogic_vector(31 downto 0) := x"90000000";
    ACCEL_SIZE      : natural := 64 * 1024           -- 64 KB (janela do periferico)
  );
  port (
    clk_i  : in  std_ulogic;
    rstn_i : in  std_ulogic;

    -- Mestre: XBUS do neorv32_top (ver rtl/core/neorv32_top.vhd, porta xbus_*)
    xbus_adr_i : in  std_ulogic_vector(31 downto 0);
    xbus_dat_i : in  std_ulogic_vector(31 downto 0);  -- dado de escrita (CPU -> perif.)
    xbus_dat_o : out std_ulogic_vector(31 downto 0);  -- dado de leitura (perif. -> CPU)
    xbus_we_i  : in  std_ulogic;
    xbus_sel_i : in  std_ulogic_vector(3 downto 0);
    xbus_stb_i : in  std_ulogic;
    xbus_cyc_i : in  std_ulogic;
    xbus_ack_o : out std_ulogic;
    xbus_err_o : out std_ulogic;

    -- Escravo 0: SDRAM
    sdram_adr_o : out std_ulogic_vector(31 downto 0);
    sdram_dat_o : out std_ulogic_vector(31 downto 0);
    sdram_dat_i : in  std_ulogic_vector(31 downto 0);
    sdram_we_o  : out std_ulogic;
    sdram_sel_o : out std_ulogic_vector(3 downto 0);
    sdram_stb_o : out std_ulogic;
    sdram_cyc_o : out std_ulogic;
    sdram_ack_i : in  std_ulogic;
    sdram_err_i : in  std_ulogic;

    -- Escravo 1: Acelerador sistolico
    accel_adr_o : out std_ulogic_vector(31 downto 0);
    accel_dat_o : out std_ulogic_vector(31 downto 0);
    accel_dat_i : in  std_ulogic_vector(31 downto 0);
    accel_we_o  : out std_ulogic;
    accel_sel_o : out std_ulogic_vector(3 downto 0);
    accel_stb_o : out std_ulogic;
    accel_cyc_o : out std_ulogic;
    accel_ack_i : in  std_ulogic;
    accel_err_i : in  std_ulogic
  );
end neorv32_xbus_wb_gateway;

architecture neorv32_xbus_wb_gateway_rtl of neorv32_xbus_wb_gateway is

  signal sel_sdram, sel_accel : std_ulogic;

  -- registra qual escravo foi selecionado no ciclo do pedido, para rotear a
  -- resposta (ack/err/dat_o) corretamente mesmo apos o endereco mudar
  signal sel_sdram_r, sel_accel_r : std_ulogic;

begin

  sel_sdram <= '1' when (unsigned(xbus_adr_i) >= unsigned(SDRAM_BASE_ADDR)) and
                        (unsigned(xbus_adr_i) <  unsigned(SDRAM_BASE_ADDR) + SDRAM_SIZE)
               else '0';

  sel_accel <= '1' when (unsigned(xbus_adr_i) >= unsigned(ACCEL_BASE_ADDR)) and
                        (unsigned(xbus_adr_i) <  unsigned(ACCEL_BASE_ADDR) + ACCEL_SIZE)
               else '0';

  -- Enderecos relativos ao inicio de cada janela (os escravos so implementam
  -- os bits de endereco necessarios para seu proprio tamanho)
  sdram_adr_o <= std_ulogic_vector(unsigned(xbus_adr_i) - unsigned(SDRAM_BASE_ADDR));
  accel_adr_o <= std_ulogic_vector(unsigned(xbus_adr_i) - unsigned(ACCEL_BASE_ADDR));

  sdram_dat_o <= xbus_dat_i;
  sdram_we_o  <= xbus_we_i;
  sdram_sel_o <= xbus_sel_i;
  sdram_stb_o <= xbus_stb_i and sel_sdram;
  sdram_cyc_o <= xbus_cyc_i and sel_sdram;

  accel_dat_o <= xbus_dat_i;
  accel_we_o  <= xbus_we_i;
  accel_sel_o <= xbus_sel_i;
  accel_stb_o <= xbus_stb_i and sel_accel;
  accel_cyc_o <= xbus_cyc_i and sel_accel;

  track_sel: process(rstn_i, clk_i)
  begin
    if (rstn_i = '0') then
      sel_sdram_r <= '0';
      sel_accel_r <= '0';
    elsif rising_edge(clk_i) then
      if (xbus_cyc_i = '1' and xbus_stb_i = '1') then
        sel_sdram_r <= sel_sdram;
        sel_accel_r <= sel_accel;
      end if;
    end if;
  end process track_sel;

  xbus_dat_o <= sdram_dat_i when sel_sdram_r = '1' else
                accel_dat_i when sel_accel_r = '1' else
                (others => '0');

  xbus_ack_o <= (sdram_ack_i and sel_sdram_r) or (accel_ack_i and sel_accel_r);

  -- Erro de barramento: escravo reportou erro, OU o endereco nao caiu em
  -- nenhuma janela mapeada durante um ciclo valido (regiao XBUS "vazia")
  xbus_err_o <= (sdram_err_i and sel_sdram_r) or (accel_err_i and sel_accel_r) or
                (xbus_cyc_i and xbus_stb_i and not sel_sdram and not sel_accel);

end neorv32_xbus_wb_gateway_rtl;
