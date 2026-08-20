#!/usr/bin/env python3
"""
send_weights.py
----------------
Ferramenta host (PC) da Fase 3 da metodologia: "Carregamento inicial dos pesos:
UART no boot". Conversa com o firmware neorv32_mnist_infer (main.c / sdram.c)
para enviar weights.bin e uma imagem MNIST de teste pela UART, disparar a
inferencia e exibir a saida.

Protocolo (ver sdram.c: sdram_uart_handshake_loop / sdram_uart_recv_blob):
    placa -> host: 'R'                (ready)
    host  -> placa: 1 byte de comando ('W'=pesos, 'I'=imagem, 'G'=go)
    (para 'W'/'I') host -> placa: 4 bytes little-endian com o tamanho N
                    host -> placa: N bytes de payload
                    placa -> host: 4 bytes little-endian ecoando N (ack)

Uso:
    python3 send_weights.py --port /dev/ttyUSB1 \
        --weights ../../../../../Documentos/tcc/ia_models/outputs/weights.bin \
        --mnist-index 0
"""
import argparse
import struct
import sys
import time

try:
    import serial
except ImportError:
    sys.exit("[ERRO] pyserial nao instalado. Rode: pip install pyserial")


def recv_ready(ser, timeout_s=30):
    t0 = time.time()
    while time.time() - t0 < timeout_s:
        b = ser.read(1)
        if b == b'R':
            return True
        if b:
            sys.stdout.write(b.decode(errors="replace"))
            sys.stdout.flush()
    return False


def send_blob(ser, cmd, data: bytes):
    if not recv_ready(ser):
        sys.exit("[ERRO] timeout aguardando 'R' (ready) da placa")
    ser.write(cmd.encode())
    ser.write(struct.pack("<I", len(data)))
    ser.write(data)
    ack = ser.read(4)
    if len(ack) != 4:
        sys.exit(f"[ERRO] timeout aguardando ack de {cmd}")
    n_ack = struct.unpack("<I", ack)[0]
    if n_ack != len(data):
        sys.exit(f"[ERRO] ack incompleto para {cmd}: enviado {len(data)}, confirmado {n_ack}")
    print(f"[OK] {cmd}: {len(data)} bytes confirmados pela placa")


def load_mnist_image_int8(index: int) -> bytes:
    """Extrai uma imagem do conjunto de teste MNIST e quantiza como o tensor de
    entrada do modelo (scale=1/255, zero_point=-128 -> int8 = uint8_pixel - 128)."""
    import numpy as np
    import tensorflow_datasets as tfds

    ds = tfds.load("mnist", split="test", as_supervised=True)
    for i, (img, label) in enumerate(tfds.as_numpy(ds)):
        if i == index:
            img_u8 = img.reshape(-1).astype(np.uint8)  # 784 bytes, HWC (C=1)
            img_i8 = (img_u8.astype(np.int16) - 128).astype(np.int8)
            print(f"[info] imagem #{index}: label real = {int(label)}")
            return img_i8.tobytes()
    sys.exit(f"[ERRO] indice {index} fora do conjunto de teste MNIST")


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--port", required=True, help="porta serial, ex.: /dev/ttyUSB1")
    ap.add_argument("--baud", type=int, default=19200)
    ap.add_argument("--weights", required=True, help="caminho para weights.bin")
    ap.add_argument("--image", help="arquivo binario com 784 bytes INT8 (28x28, HWC)")
    ap.add_argument("--mnist-index", type=int, help="indice no conjunto de teste MNIST (usa tensorflow_datasets)")
    args = ap.parse_args()

    if not args.image and args.mnist_index is None:
        sys.exit("[ERRO] especifique --image ou --mnist-index")

    with open(args.weights, "rb") as f:
        weights = f.read()

    if args.image:
        with open(args.image, "rb") as f:
            image = f.read()
        if len(image) != 784:
            sys.exit(f"[ERRO] imagem deveria ter 784 bytes, tem {len(image)}")
    else:
        image = load_mnist_image_int8(args.mnist_index)

    ser = serial.Serial(args.port, args.baud, timeout=5)

    print("[*] enviando pesos...")
    send_blob(ser, 'W', weights)

    print("[*] enviando imagem...")
    send_blob(ser, 'I', image)

    if not recv_ready(ser):
        sys.exit("[ERRO] timeout aguardando 'R' antes do go")
    ser.write(b'G')
    print("[*] 'go' enviado -- lendo saida da inferencia (Ctrl+C para sair)...\n")

    try:
        while True:
            data = ser.read(256)
            if data:
                sys.stdout.write(data.decode(errors="replace"))
                sys.stdout.flush()
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
