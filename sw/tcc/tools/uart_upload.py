#!/usr/bin/env python3
"""
Upload an executable via serial port (UART) to the NEORV32 bootloader.

Portable replacement for uart_upload.sh (which needs bash + a working `stty`;
the MSYS/Git-Bash `stty` cannot configure Windows COM ports). Same protocol and
same throttled 16-byte chunking as the shell script, but only needs pyserial.

If the upload is successful, the executable is run automatically.
Reset the processor before starting the upload.

Usage:   python uart_upload.py <serial port> <NEORV32 executable>
Example: python uart_upload.py COM17 path/to/neorv32_exe.bin
         python uart_upload.py /dev/ttyUSB1 path/to/neorv32_exe.bin
"""
import sys
import time

BAUD = 19200
# Envio pausado: 16 bytes a cada 10ms (~1600 B/s), ABAIXO dos 1920 B/s que 19200
# baud comporta. Testado: enviar em rajada continua falha mesmo com um adaptador
# FTDI bom, entao a pausa nao e (so) por causa do CH340 -- o gargalo esta em
# quanto o bootloader consegue absorver, nao no cabo. Nao remover sem testar.
CHUNK = 16
CHUNK_DELAY_S = 0.01


def upload(ser, data, baud=BAUD, log=sys.stdout):
    """Send `data` to the bootloader on `ser`; return True on success."""
    # "baud" bits per second; 10 bits per byte (incl. START and STOP); plus margin
    timeout_s = len(data) // (baud // 10) + 10

    ser.reset_input_buffer()  # drain any stale buffered input

    log.write("Uploading executable (%d bytes)... " % len(data))
    log.flush()
    ser.write(b" u")  # skip auto-boot (SPACE) and start upload ('u')
    if CHUNK <= 0:
        ser.write(data)
        ser.flush()
    else:
        for i in range(0, len(data), CHUNK):
            ser.write(data[i:i + CHUNK])
            ser.flush()
            if CHUNK_DELAY_S:
                time.sleep(CHUNK_DELAY_S)

    # wait for the bootloader response
    buf = b""
    deadline = time.time() + timeout_s
    while time.time() < deadline and b"OK" not in buf:
        buf += ser.read(ser.in_waiting or 1)

    if b"OK" in buf:
        log.write("OK\n")
        log.write("Booting executable...\n")
        ser.write(b"e")
        ser.flush()
        return True

    if buf:
        log.write("\nERROR! Invalid bootloader response.\n")
        log.write("DEBUG raw response: %r\n" % buf)
    else:
        log.write("\nERROR! Bootloader response timeout (%d seconds).\n" % timeout_s)
    log.write("Check configuration, reset processor and try again.\n")
    return False


def main(argv):
    if len(argv) != 3:
        sys.stdout.write(__doc__)
        return 0

    try:
        import serial
    except ImportError:
        sys.exit("[ERRO] pyserial nao instalado. Rode: pip install pyserial")

    port, path = argv[1], argv[2]
    with open(path, "rb") as f:
        data = f.read()

    sys.stdout.write("Opening serial port (%s)... " % port)
    sys.stdout.flush()
    try:
        ser = serial.Serial(port, BAUD, bytesize=serial.EIGHTBITS,
                            parity=serial.PARITY_NONE, stopbits=serial.STOPBITS_ONE,
                            timeout=0.2, write_timeout=10)
    except serial.SerialException as e:
        sys.exit("\nERROR! Cannot open %s: %s" % (port, e))
    sys.stdout.write("OK\n")

    with ser:
        return 0 if upload(ser, data) else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
