## Simulation Sources

Default testbench, helper modules and GDHL simulation scripts.

:books: See [UG: Simulating the Processor](https://stnolting.github.io/neorv32/ug/#_simulating_the_processor).

## Simulações do TCC (acelerador sistólico + SDRAM, DE2-115)

Testadas com o GHDL 6.0.0 (mcode). `GHDL=<caminho>` se ele não estiver no PATH.

| Script | O que roda | Tempo |
| --- | --- | --- |
| `run_accel_sim.sh` | Testbenches unitárias: acelerador em 8×8 e 16×16 (`neorv32_systolic_wb_accelerator_tb`), matmul 8×8×8, controlador SDRAM com mestre de `stb` de um ciclo (estilo XBUS) | segundos |
| `run_soc_sim.sh [TILE]` | O top-level da placa inteiro (`neorv32_de2115_soc_tb`) com o firmware `sw/example/accel_dma_test` gravado na IMEM: matmul e matvec pelos caminhos CPU, DMA e DMA com sobreposição, conferidos contra software | 10–20 min |
| `run_infer_sim.sh [TILE] [MODO] [IMAGEM]` | O mesmo SoC com o firmware de inferência (`make SIM=1`): pesos e imagem carregados no modelo da SDRAM no tempo 0, logits conferidos contra o `expected.txt` do modelo (`MODEL_DIR`) | horas |

Arquivos de apoio: `neorv32_sdram_model.vhd` (modelo comportamental, com
`ROW_BITS` e carga de arquivos binários), `sdram_clk_pll_core_sim.vhd` (substitui o
ALTPLL, que só existe no Quartus) e `sim_uart_rx.vhd` (texto do pino TX).

O GHDL mcode relê os fontes `.vhd` no `-r`. Não edite nem apague um fonte, nem o
próprio script, enquanto uma simulação dele estiver rodando. Os scripts copiam a
imagem da IMEM para a pasta de trabalho (`SIM_TAG` escolhe outra pasta, para
rodar em paralelo).
