  -- ================================================================================ --
  -- NEORV32 SoC - Systolic Array Accelerator (Wishbone Interface)                     --
  -- -------------------------------------------------------------------------------- --
  -- Versao do acelerador sistolico com interface Wishbone classica (non-pipelined)    --
  -- Substitui o modulo neorv32_cfs para integrar o array sistolico via barramento WB  --
  -- -------------------------------------------------------------------------------- --
  -- Mapa de memoria (enderecos em bytes, relativos ao BASE do periferico). T e o     --
  -- tamanho do array (generic ARRAY_SIZE, 8 ou 16):                                  --
  --   0x000  CTRL        [2] irq_clear, [1] clear, [0] start                         --
  --   0x004  STATUS      [2] irq_pending, [1] done, [0] busy                         --
  --   0x008  CONFIG      Reservado (leitura/escrita livre, uso futuro)                --
  --   0x00C  INFO        Somente leitura: [7:0] linhas, [15:8] colunas do array       --
  --   0x100  WEIGHT      Tile de pesos TxT INT8 (T*T/4 words, row-major)              --
  --   0x500  ACT         Tile de ativacoes TxT INT8 (T*T/4 words, row-major)          --
  --   0x900  RESULT      Resultado TxT INT32 (T*T words, somente leitura, row-major)  --
  -- Com T = 16 as janelas vao ate 0x1FC, 0x5FC e 0xCFC, sem sobreposicao.            --
  -- -------------------------------------------------------------------------------- --
  -- Semantica de calculo: um pulso de start multiplica o tile de ativacoes TxT pelo   --
  -- tile de pesos TxT (stationary), produzindo RESULT = ACT @ WEIGHT (INT32, TxT).    --
  -- RESULT[r*T+c] = sum_k ACT[r*T+k] * WEIGHT[k*T+c]. Ver tcc_systolic_array.vhd. --
  -- WEIGHT pode ser reescrito durante o calculo (o array ja copiou os pesos no ciclo  --
  -- seguinte ao start); ACT nao, porque e lido linha a linha ate o fim da operacao.  --
  -- -------------------------------------------------------------------------------- --
  -- Licensed under the BSD-3-Clause license                                           --
  -- ================================================================================ --

  library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;

  library neorv32;
  use neorv32.neorv32_package.all;

  -- Entidade: interface Wishbone classica do acelerador sistolico
  entity neorv32_systolic_wb_accelerator is
    generic (
      ARRAY_SIZE : natural range 2 to 16 := 8  -- array ARRAY_SIZE x ARRAY_SIZE (8 ou 16)
    );
    port (
      -- Clock e reset (ativo-baixo, convencao NEORV32)
      clk_i   : in  std_ulogic;                        -- Clock global do sistema
      rstn_i  : in  std_ulogic;                        -- Reset sincrono ativo-baixo

      -- Interrupcao
      irq_o   : out std_ulogic;                        -- Sinal de IRQ para o processador

      -- Sinais do barramento Wishbone (escravo)
      wb_adr_i : in  std_ulogic_vector(31 downto 0);   -- Endereco (word-aligned)
      wb_dat_i : in  std_ulogic_vector(31 downto 0);   -- Dados de escrita (CPU -> acelerador)
      wb_dat_o : out std_ulogic_vector(31 downto 0);   -- Dados de leitura (acelerador -> CPU)
      wb_we_i  : in  std_ulogic;                        -- Write Enable: '1' = escrita, '0' = leitura
      wb_sel_i : in  std_ulogic_vector(3 downto 0);    -- Byte select (1 byte por bit)
      wb_stb_i : in  std_ulogic;                        -- Strobe: indica ciclo valido
      wb_cyc_i : in  std_ulogic;                        -- Cycle: indica barramento em uso
      wb_ack_o : out std_ulogic;                        -- Acknowledge: transacao concluida
      wb_err_o : out std_ulogic                         -- Error: erro na transacao
    );
  end neorv32_systolic_wb_accelerator;

  -- Arquitetura: logica RTL do acelerador com interface Wishbone
  architecture neorv32_systolic_wb_rtl of neorv32_systolic_wb_accelerator is

    -- Dimensoes do array sistolico. O array e quadrado: o wrapper e
    -- neorv32_systolic_array indexam act_cols_i por linha, o que so fecha com
    -- ARRAY_ROWS = ARRAY_COLS.
    constant ARRAY_ROWS : natural := ARRAY_SIZE;  -- PEs por coluna
    constant ARRAY_COLS : natural := ARRAY_SIZE;  -- PEs por linha
    constant DATA_WIDTH : natural := 8;   -- Largura dos dados de entrada (INT8)
    constant ACC_WIDTH  : natural := 32;  -- Largura do acumulador (INT32)

    -- Total de entradas em cada memoria
    constant WEIGHT_ENTRIES : natural := ARRAY_ROWS * ARRAY_COLS;  -- bytes de pesos (64 ou 256)
    constant ACT_ENTRIES    : natural := ARRAY_ROWS * ARRAY_COLS;  -- bytes de ativacoes
    constant RESULT_ENTRIES : natural := ARRAY_ROWS * ARRAY_COLS;  -- words de 32 bits

    -- Numero de words (32 bits) necessarias para armazenar pesos e ativacoes
    constant WEIGHT_WORDS : natural := WEIGHT_ENTRIES / 4;  -- 16 ou 64 words
    constant ACT_WORDS    : natural := ACT_ENTRIES / 4;     -- 16 ou 64 words

    -- Indices (em words de 32 bits, wb_adr_i(15 downto 2)) dos registradores/janelas
    -- mapeados no barramento Wishbone. Casa exatamente com o firmware em
    -- sw/tcc/test_systolic_accel/main.c e sw/tcc/mnist_infer/accel_driver.c
    constant REG_CTRL        : natural := 16#000# / 4;  -- 0x000  CTRL
    constant REG_STATUS      : natural := 16#004# / 4;  -- 0x004  STATUS
    constant REG_CONFIG      : natural := 16#008# / 4;  -- 0x008  CONFIG
    constant REG_INFO        : natural := 16#00C# / 4;  -- 0x00C  INFO (somente leitura)
    constant WEIGHT_BASE_W   : natural := 16#100# / 4;  -- 0x100  WEIGHT
    constant ACT_BASE_W      : natural := 16#500# / 4;  -- 0x500  ACT
    constant RESULT_BASE_W   : natural := 16#900# / 4;  -- 0x900  RESULT

    -- INFO: o firmware confere o tamanho do array antes de usar o acelerador,
    -- para recusar um bitstream de tamanho diferente do que foi compilado.
    constant INFO_VALUE : std_ulogic_vector(31 downto 0) :=
      x"0000" & std_ulogic_vector(to_unsigned(ARRAY_COLS, 8)) & std_ulogic_vector(to_unsigned(ARRAY_ROWS, 8));

    -- Tipos de memoria: arrays de std_ulogic_vector
    type weight_mem_t  is array (0 to WEIGHT_ENTRIES-1) of std_ulogic_vector(DATA_WIDTH-1 downto 0);
    type act_mem_t     is array (0 to ACT_ENTRIES-1)    of std_ulogic_vector(DATA_WIDTH-1 downto 0);
    type result_mem_t  is array (0 to RESULT_ENTRIES-1)  of std_ulogic_vector(ACC_WIDTH-1 downto 0);

    -- Instancias das memorias internas
    signal weight_mem : weight_mem_t;    -- Memoria de pesos (INT8, 64 entradas)
    signal act_mem    : act_mem_t;       -- Memoria de ativacoes (INT8, 64 entradas)
    signal result_mem : result_mem_t;    -- Memoria de resultados (INT32, 64 entradas)

    -- Registradores de controle e status acessados via Wishbone
    signal ctrl_reg   : std_ulogic_vector(31 downto 0);  -- Registrador de controle
    signal config_reg : std_ulogic_vector(31 downto 0);  -- Registrador de configuracao
    signal status_reg : std_ulogic_vector(31 downto 0);  -- Registrador de status (somente leitura)

    -- Sinais de controle do array sistolico
    signal array_start : std_ulogic;  -- Pulso para iniciar a computacao
    signal array_clear : std_ulogic;  -- Sinal para limpar/resetar o array
    signal array_done  : std_ulogic;  -- Indica que o array terminou a computacao
    signal array_busy  : std_ulogic;  -- Indica que o array esta processando
    -- busy/done da OPERACAO INTEIRA (tile TxT), distintos do done do array, que
    -- pulsa a cada uma das T linhas. O software precisa do nivel de operacao:
    -- polling em array_done retornava logo apos a linha 0, lendo um tile com as
    -- outras 7 linhas ainda nao computadas.
    signal op_busy : std_ulogic;
    signal op_done : std_ulogic;

    -- Barramentos de dados entre o acelerador e o array sistolico
    signal act_cols_to_array : std_ulogic_vector(ARRAY_COLS*DATA_WIDTH-1 downto 0);            -- Ativacoes (T x INT8, uma linha do tile)
    signal weight_to_array   : std_ulogic_vector(ARRAY_ROWS*ARRAY_COLS*DATA_WIDTH-1 downto 0);  -- Tile de pesos completo (T*T x INT8)
    signal result_from_array : std_ulogic_vector(ARRAY_COLS*ACC_WIDTH-1 downto 0);              -- Resultados (T x INT32, uma linha do tile)

    -- FSM: tipo enumerado dos estados da maquina de estados de computacao
    type fsm_t is (
      S_IDLE,          -- Ocioso: aguardando comando de start
      S_LOAD_WEIGHTS,  -- Carregando pesos no array sistolico
      S_LOAD_ACTS,     -- Carregando ativacoes no array sistolico
      S_COMPUTE,       -- Aguardando o array terminar a computacao
      S_STORE_RESULTS, -- Armazenando resultados na memoria
      S_DONE           -- Computacao concluida, volta ao idle
    );

    -- Sinais da FSM de computacao
    signal fsm_state : fsm_t;                          -- Estado atual da FSM
    signal tile_row  : natural range 0 to ARRAY_ROWS-1;  -- Linha atual do tile de ativacoes (para iteracao)

    -- Sinais de deteccao de borda para geracao de IRQ
    signal prev_done    : std_ulogic;  -- Valor anterior de op_done (deteccao de borda de subida)
    signal irq_pending  : std_ulogic;  -- Flag de interrupcao pendente

    -- Deteccao de borda do bit start (ctrl_reg(0)): sem isso, como o software
    -- nunca zera esse bit apos disparar, a FSM re-dispara toda a operacao de
    -- T linhas assim que volta a S_IDLE (busy=0 com start ainda em '1'),
    -- entrando em loop automatico invisivel para o software.
    signal prev_ctrl_start : std_ulogic;

  begin

    -- Atribuicao dos bits do registrador de status (somente leitura)
    status_reg(0)          <= op_busy;        -- Bit 0: operacao (tile TxT) em curso
    status_reg(1)          <= op_done;        -- Bit 1: operacao concluida
    status_reg(2)          <= irq_pending;    -- Bit 2: interrupcao pendente
    status_reg(31 downto 3) <= (others => '0');  -- Bits 31..3: reservados (zero)

    -- Sinal de clear vem do bit 1 do registrador de controle
    array_clear <= ctrl_reg(1);

    -- Processo: Geracao de interrupcao (IRQ)
    -- Gera uma interrupcao na borda de subida de op_done, o fim da operacao
    -- inteira. A versao anterior usava array_done, que pulsa a cada linha do
    -- tile: a IRQ subia depois da linha 0, com o resultado ainda incompleto
    -- (o mesmo engano que o polling ja tinha corrigido, ver op_busy/op_done).
    -- A IRQ permanece pendente ate o software limpar via ctrl_reg(2)
    irq_gen : process(rstn_i, clk_i)
    begin
      if (rstn_i = '0') then
        -- Reset: limpa todos os sinais de IRQ
        prev_done   <= '0';
        irq_pending <= '0';
        irq_o       <= '0';
      elsif rising_edge(clk_i) then
        -- Registra o valor anterior de op_done para detectar borda
        prev_done <= op_done;

        -- Detecta borda de subida: op_done passou de 0 para 1
        if (op_done = '1' and prev_done = '0') then
          irq_pending <= '1';  -- Marca IRQ como pendente
        end if;

        -- Software limpa a IRQ escrevendo 1 no bit 2 de CTRL
        if (ctrl_reg(2) = '1') then
          irq_pending <= '0';  -- Limpa flag de interrupcao
        end if;

        -- Sinal de IRQ ativo enquanto houver interrupcao pendente
        irq_o <= irq_pending;
      end if;
    end process irq_gen;

    -- Processo: Escravo Wishbone
    -- Decodifica os ciclos de leitura/escrita no barramento Wishbone
    -- e direciona os dados para os registradores e memorias internas.
    -- Enderecamento por word (wb_adr_i(15 downto 2)): ver mapa de memoria no cabecalho.
    wb_slave : process(rstn_i, clk_i)
      variable addr_idx : natural range 0 to 16383;  -- Indice de word (extraido do endereco)
    begin
      if (rstn_i = '0') then
        -- Reset: inicializa todos os registradores e saidas Wishbone
        ctrl_reg  <= (others => '0');
        config_reg <= (others => '0');
        wb_ack_o  <= '0';
        wb_err_o  <= '0';
        wb_dat_o  <= (others => '0');

      elsif rising_edge(clk_i) then
        -- Acknowledge e error sao pulsados por 1 ciclo
        wb_ack_o <= '0';
        wb_err_o <= '0';

        -- Verifica se ha um ciclo Wishbone valido (cyc + stb)
        if (wb_cyc_i = '1' and wb_stb_i = '1') then
          -- Extrai o indice de word do endereco (word-aligned, bits 15:2)
          addr_idx := to_integer(unsigned(wb_adr_i(15 downto 2)));

          -- Acknowledge: indica que a transacao sera processada neste ciclo
          wb_ack_o <= '1';

          if (wb_we_i = '1') then
            -- Escrita: CPU esta enviando dados para o acelerador
            if (addr_idx = REG_CTRL) then
              -- Bit 0: start (pulso para iniciar computacao)
              -- Bit 1: clear (resetar o array sistolico)
              -- Bit 2: ack_irq (limpar interrupcao pendente)
              ctrl_reg <= wb_dat_i;

            elsif (addr_idx = REG_CONFIG) then
              config_reg <= wb_dat_i;

            elsif (addr_idx >= WEIGHT_BASE_W and addr_idx < WEIGHT_BASE_W + WEIGHT_WORDS) then
              -- Escreve 4 bytes de peso (INT8 cada) na janela de pesos
              for i in 0 to 3 loop
                if (wb_sel_i(i) = '1') then
                  weight_mem((addr_idx - WEIGHT_BASE_W) * 4 + i) <= wb_dat_i((i+1)*8-1 downto i*8);
                end if;
              end loop;

            elsif (addr_idx >= ACT_BASE_W and addr_idx < ACT_BASE_W + ACT_WORDS) then
              -- Escreve 4 bytes de ativacao (INT8 cada) na janela de ativacoes
              for i in 0 to 3 loop
                if (wb_sel_i(i) = '1') then
                  act_mem((addr_idx - ACT_BASE_W) * 4 + i) <= wb_dat_i((i+1)*8-1 downto i*8);
                end if;
              end loop;

            end if;
            -- Escritas na janela RESULT (somente leitura) e em enderecos
            -- desconhecidos sao ignoradas (ainda geram ack, sem efeito).

          else
            -- Leitura: CPU esta lendo dados do acelerador
            wb_dat_o <= (others => '0');  -- Valor padrao: zero

            if (addr_idx = REG_CTRL) then
              wb_dat_o <= ctrl_reg;

            elsif (addr_idx = REG_STATUS) then
              wb_dat_o <= status_reg;

            elsif (addr_idx = REG_CONFIG) then
              wb_dat_o <= config_reg;

            elsif (addr_idx = REG_INFO) then
              wb_dat_o <= INFO_VALUE;

            elsif (addr_idx >= RESULT_BASE_W and addr_idx < RESULT_BASE_W + RESULT_ENTRIES) then
              -- Le 32 bits (INT32) da memoria de resultados
              wb_dat_o <= result_mem(addr_idx - RESULT_BASE_W);

            end if;
          end if;
        end if;
      end if;
    end process wb_slave;

    -- Processo: FSM de computacao do array sistolico
    -- Controla o carregamento de dados, execucao e armazenamento de resultados
    -- Baseado no loop: carrega pesos -> carrega ativacoes -> computa -> store -> repete
    compute_fsm : process(rstn_i, clk_i)
      variable start_req : std_ulogic;  -- Requisicao de inicio (start e nao-busy e nao-clear)
    begin
      if (rstn_i = '0') then
        -- Reset: volta ao estado ocioso
        fsm_state           <= S_IDLE;
        array_start         <= '0';
        op_busy             <= '0';
        op_done             <= '0';
        tile_row            <= 0;
        act_cols_to_array   <= (others => '0');
        weight_to_array     <= (others => '0');
        prev_ctrl_start     <= '0';

      elsif rising_edge(clk_i) then
        -- array_start e um pulso de 1 ciclo
        array_start <= '0';

        -- Condicao de inicio: borda de subida do bit 0 de CTRL (nao o nivel),
        -- array nao-busy, e sem clear ativo. Ver comentario de prev_ctrl_start.
        start_req := ctrl_reg(0) and (not prev_ctrl_start) and (not array_busy) and (not array_clear);
        prev_ctrl_start <= ctrl_reg(0);

        if (array_clear = '1') then
          op_busy <= '0';
          op_done <= '0';
        end if;

        case fsm_state is
          -- Estado ocioso: aguarda comando de start via CTRL
          when S_IDLE =>
            if (start_req = '1') then
              fsm_state <= S_LOAD_WEIGHTS;  -- Inicia carregamento do tile de pesos
              tile_row  <= 0;                -- Comeca pela primeira linha de ativacoes
              op_busy   <= '1';
              op_done   <= '0';
            end if;

          -- Carrega o tile de pesos TxT completo no array sistolico (uma vez por operacao)
          when S_LOAD_WEIGHTS =>
            for row in 0 to ARRAY_ROWS-1 loop
              for col in 0 to ARRAY_COLS-1 loop
                weight_to_array((row*ARRAY_COLS+col+1)*DATA_WIDTH-1 downto (row*ARRAY_COLS+col)*DATA_WIDTH) <=
                  weight_mem(row * ARRAY_COLS + col);
              end loop;
            end loop;
            fsm_state <= S_LOAD_ACTS;  -- Proximo: carregar ativacoes

          -- Carrega T ativacoes (1 por linha de PEs) no array sistolico
          when S_LOAD_ACTS =>
            for i in 0 to ARRAY_COLS-1 loop
              act_cols_to_array((i+1)*DATA_WIDTH-1 downto i*DATA_WIDTH) <=
                act_mem(tile_row * ARRAY_COLS + i);
            end loop;
            array_start <= '1';  -- Pulso de inicio para o array sistolico
            fsm_state <= S_COMPUTE;  -- Proximo: aguardar resultado

          -- Aguarda o array sistolico terminar a computacao.
          -- "array_start = '0'" evita uma condicao de corrida: no proprio
          -- ciclo em que array_start e pulsado (entrada neste estado vinda
          -- de S_LOAD_ACTS), o array ainda nao processou o pulso -- seu
          -- done_reg so e zerado no ciclo SEGUINTE. Sem essa guarda, o
          -- done_reg obsoleto (ainda '1' da linha anterior) faz a FSM
          -- concluir precocemente que a linha atual ja terminou, capturando
          -- resultado apos 1 ciclo em vez dos 15 necessarios. So afeta a
          -- linha 0 corretamente por acaso (done_reg comeca zerado no
          -- reset); linhas seguintes ficavam sistematicamente erradas.
          -- Bug real encontrado via simulacao GHDL (neorv32_systolic_matmul_tb).
          when S_COMPUTE =>
            if (array_done = '1' and array_start = '0') then
              -- Armazena os resultados de cada coluna na memoria
              for i in 0 to ARRAY_COLS-1 loop
                result_mem(tile_row * ARRAY_COLS + i) <=
                  result_from_array((i+1)*ACC_WIDTH-1 downto i*ACC_WIDTH);
              end loop;
              fsm_state <= S_STORE_RESULTS;  -- Proximo: verificar se ha mais linhas
            end if;

          -- Verifica se todas as linhas (tiles) foram processadas
          when S_STORE_RESULTS =>
            if (tile_row < ARRAY_ROWS - 1) then
              -- Ainda ha linhas para processar: carrega proxima ativacao
              tile_row  <= tile_row + 1;
              fsm_state <= S_LOAD_ACTS;
            else
              -- Todas as linhas processadas: computacao concluida
              fsm_state <= S_DONE;
            end if;

          -- Computacao concluida: volta ao estado ocioso
          when S_DONE =>
            fsm_state <= S_IDLE;
            op_busy   <= '0';
            op_done   <= '1';  -- so agora as T linhas estao em result_mem

        end case;
      end if;
    end process compute_fsm;

    -- Instanciacao do array sistolico TxT
    -- Conecta os sinais internos do acelerador ao componente do array
    systolic_array_inst : entity work.neorv32_systolic_array
      generic map (
        ARRAY_ROWS => ARRAY_ROWS,  -- T linhas
        ARRAY_COLS => ARRAY_COLS,  -- T colunas
        DATA_WIDTH  => DATA_WIDTH,  -- 8 bits por dado
        ACC_WIDTH   => ACC_WIDTH   -- 32 bits por acumulador
      )
      port map (
        clk_i      => clk_i,                  -- Clock do sistema
        rstn_i     => rstn_i,                 -- Reset ativo-baixo
        start_i    => array_start,            -- Pulso de inicio da computacao
        clear_i    => array_clear,            -- Sinal de clear do array
        act_cols_i => act_cols_to_array,      -- Linha de ativacoes atual (T x INT8)
        weight_i   => weight_to_array,        -- Tile de pesos completo (64xINT8)
        done_o     => array_done,             -- Sinal de conclusao
        busy_o     => array_busy,             -- Sinal de ocupado
        result_o   => result_from_array       -- Resultados da linha atual (T x INT32)
      );

  end neorv32_systolic_wb_rtl;