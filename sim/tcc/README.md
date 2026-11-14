# Simulações do TCC (acelerador sistólico + SDRAM, DE2-115)

Testadas com o GHDL 6.0.0 (mcode). `GHDL=<caminho>` se ele não estiver no PATH.
Os scripts podem ser chamados de qualquer pasta: eles mudam para a raiz do
repositório antes de rodar.

| Script | O que roda | Tempo |
| --- | --- | --- |
| `run_accel_sim.sh` | Testbenches unitárias: acelerador (`tcc_systolic_wb_accelerator_tb.vhd`), matmul 8×8×8 e controlador SDRAM com o modelo de memória | segundos |

Arquivo de apoio: `tcc_sdram_model.vhd` (modelo comportamental da SDRAM).

Arquivos e entidades têm o prefixo `tcc_`.

A simulação do SoC inteiro com o firmware, o caminho de DMA do acelerador e a
correção do controlador de SDRAM (sessão 3 do diário, só em simulação) estão no
ramo `tcc-dma-experimental`, fora da versão medida no TCC.

O GHDL mcode relê os fontes `.vhd` no `-r`. Não edite nem apague um fonte, nem o
próprio script, enquanto uma simulação dele estiver rodando. Os scripts copiam a
imagem da IMEM para a pasta de trabalho (`SIM_TAG` escolhe outra pasta, para
rodar em paralelo).
