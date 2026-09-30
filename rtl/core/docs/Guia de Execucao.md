# Guia de Execução — Acelerador Sistólico + Inferência na DE2-115

Passo a passo para compilar, gravar e rodar o projeto do zero, sem cair nas
armadilhas já mapeadas (o porquê de cada uma está no `Diario de Bring-up.md`).

A DE2-115 precisa de **dois** cabos: o USB-Blaster (JTAG, só programa a FPGA) e um
cabo serial no conector **RS-232 DB9** da placa (UART). Não use o cabo do Blaster
para UART.

**Duas velocidades de UART.** O bootloader fica em **19200** baud (fixo no
bitstream) e só recebe o firmware. A aplicação usa **115200** baud para a saída de
texto e para receber pesos e imagem. Configure o terminal de acordo com a etapa.

---

## 0. Ambiente (uma vez só)

```bash
# Toolchain RISC-V
export PATH="/opt/riscv-none-elf-gcc/bin:$PATH"

# Quartus por linha de comando (a GUI do 18.1 trava neste ambiente)
export QUARTUS_ROOTDIR=~/intelFPGA_lite/18.1/quartus
export PATH="$QUARTUS_ROOTDIR/linux64:$QUARTUS_ROOTDIR/bin:$PATH"
export LD_LIBRARY_PATH="$QUARTUS_ROOTDIR/linux64:$QUARTUS_ROOTDIR/../lib/usr/lib/x86_64-linux-gnu:$LD_LIBRARY_PATH"
```

O projeto também compila no Quartus 25.1. Ele regenera os arquivos do PLL mudando
só strings de versão, sem alterar parâmetros.

Descubra a porta serial da UART:
```bash
ls /dev/ttyUSB*
```
Se houver mais de uma, abra `minicom -D /dev/ttyUSBX -b 19200`, resete a placa
(KEY0) e veja em qual aparece o banner do bootloader NEORV32. Use esse `X` em todos
os passos abaixo. No Windows a porta é `COMn`.

---

## 1. Compilar e gravar o hardware

```bash
cd ~/neorv32/rtl/core
quartus_sh --flow compile neorv32_mnist_accel
```

Espera-se `Full Compilation was successful. 0 errors`. O `.sof` fica em
`output_files_mnist_accel/neorv32_mnist_accel.sof`. Grave com o Programmer ou com
`quartus_pgm`.

Com o SDC atual, o relatório de timing cobre também a interface com a SDRAM.
Uma violação nesse domínio é real, não ruído. A defasagem do `DRAM_CLK` (180°,
`-10000` ps) foi validada em hardware: **não troque pela fase que o TimeQuest
sugerir** sem testar na placa, porque 0 ps tem folga maior no relatório e desloca
todo acesso em uma palavra (Diário, 9.3).

---

## 2. Compilar e subir o firmware

```bash
cd ~/neorv32/sw/example/neorv32_mnist_infer
make clean_all exe
```

Upload via bootloader (19200 baud). **A ordem e o tempo importam**:

1. Feche qualquer terminal aberto na porta serial.
2. Aperte o reset (KEY0).
3. Logo em seguida (o bootloader só escuta por alguns segundos), rode:
   ```bash
   make UART_TTY=/dev/ttyUSBX upload      # Linux
   make upload_py UART_TTY=COM5           # Windows (pip install pyserial)
   ```
   No Windows, `upload` não funciona porque o `stty` do MSYS/Git Bash não configura
   portas COM. Use `upload_py`.
4. Se der timeout esperando o bootloader, o reset foi cedo demais ou a placa não está
   com o `.sof` certo. Reprograme, resete e tente de novo.

Depois de "Booting executable...", abra o terminal **a 115200**:
```bash
minicom -D /dev/ttyUSBX -b 115200
```

---

## 3. O que aparece no boot

Na saída serial e no LCD da placa:

1. **Diagnóstico da SDRAM** (`sdram_diag.c`): quatro regiões, vários padrões,
   incluindo o endereço como dado. Espera-se
   `TOTAL: 0 palavras com erro em 5120` e `===== FIM (PASS) =====`. O LCD mostra
   "testando SDRAM".
2. **Benchmark SW × HW** (matmul 8×8×8): ciclos de CPU e de acelerador, e
   "Resultados identicos". Referência: ~33 350 × ~18 533 ciclos, ganho de ~1,8×.
3. **Espera pelo handshake**: o LCD mostra "Aguardando / imagem via UART".

Se o diagnóstico der `FAIL`, **não siga para a inferência**: os resultados seriam
números errados com cara de certos. O mapa de bits com erro impresso pelo
diagnóstico diz se o problema é de endereço ou de dado.

O contador de access faults retentados não fica em zero. Isso é esperado: há
milhares de faults transitórios por inferência, todos recuperados pelo retry
(Diário, 4.3 e 10).

---

## 4. Enviar pesos + imagem e rodar a inferência

Feche o minicom (dois processos não podem usar a porta) e rode:

```bash
cd ~/neorv32/sw/example/neorv32_mnist_infer
python3 tools/send_weights.py --port /dev/ttyUSBX --baud 115200 \
  --weights caminho/para/weights.bin \
  --image caminho/para/imagem.bin
```

- `--baud 115200` é obrigatório na prática: o padrão do script é 19200 e o firmware
  escuta a 115200.
- `--image` recebe um arquivo de 784 bytes INT8 (28×28). `--mnist-index N` pega a
  imagem N do conjunto de teste do MNIST via `tensorflow_datasets`.
- A transferência dos ~422 KB de pesos leva cerca de 40 s. O LCD mostra "Recebendo
  pesos", depois "Pesos na SDRAM", "Recebendo imagem" e "Inferindo..." com o nome
  da camada.

Ao final, a saída serial mostra os logits e a classe prevista, e o LCD mostra
"Classe: N / KEY1 = proxima".

**Próximas imagens**: aperte **KEY1**. O firmware volta a esperar o handshake e os
pesos continuam na SDRAM, então basta enviar só a imagem:
```bash
python3 tools/send_weights.py --port /dev/ttyUSBX --baud 115200 --image outra.bin
```
Reenvie os pesos só depois de um reset ou de trocar de modelo.

---

## 5. Regenerar `weights.bin` / `model_meta.h`

O pipeline atual usa `build_mnist_int8.py` (PyTorch), que gera `weights.bin`,
`model_meta.h` e a referência bit-exata (`out/expected.txt`, ativações por camada em
`out/golden/`). Esse script ficou no ambiente onde a sessão 2 foi feita e **não está
neste repositório**.

Regras:
- `weights.bin` e `model_meta.h` precisam vir **da mesma execução** do mesmo
  gerador. Pesos novos com escalas antigas não dão erro, só números errados. MNIST e
  Fashion-MNIST têm exatamente o mesmo tamanho (422 344 bytes), então o tamanho não
  denuncia a troca.
- Depois de trocar o `model_meta.h`, recompile e refaça o upload do firmware
  (passo 2).
- O `model_meta.h` versionado no `main` hoje é o do **Fashion-MNIST**.
- O antigo `ia_models/src/export_weights.py` (TFLite) usa quantização por canal. O
  firmware do `main` usa uma escala por camada. Para voltar a esse pipeline, é
  preciso reaplicar a correção do branch `backup/main-per-channel-quantization`
  (Diário, seção 6).

---

## Checklist rápido se algo não funcionar

- [ ] Cabo serial no RS-232 DB9, não no Blaster?
- [ ] `/dev/ttyUSBX` ainda é o mesmo? Reconectar o cabo pode trocar o número.
- [ ] Terminal a **19200** para o bootloader e a **115200** para a aplicação?
- [ ] `send_weights.py` com `--baud 115200`?
- [ ] Reset feito logo antes do `make upload`?
- [ ] Nenhum terminal segurando a porta durante `make upload` ou `send_weights.py`?
- [ ] Placa gravada com o `.sof` mais recente?
- [ ] Diagnóstico da SDRAM em `PASS` antes de enviar pesos?
- [ ] `weights.bin` e `model_meta.h` do mesmo gerador e da mesma execução?
- [ ] A placa reiniciou sozinha? Já aconteceu, sem causa identificada (Diário, 10).
      Resete e comece do passo 2.
