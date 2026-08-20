#!/usr/bin/env bash

# Simple script to upload an executable to the default NEORV32 bootloader

set -e

# Default baud rate
BAUD=19200

# check arguments; show help text
if [ $# -ne 2 ]
then
  printf "Upload an executable via serial port (UART) to the NEORV32 bootloader.\n"
  printf "If the upload is successful, the executable will be run automatically.\n"
  printf "Reset processor before starting the upload.\n\n"
  printf "Usage:   ./uart_upload.sh <serial port> <NEORV32 executable>\n"
  printf "Example: ./uart_upload.sh /dev/ttyS6 path/to/neorv32_exe.bin\n"
  exit 0
fi

# timeout to make sure there is enough time for the file to be sent in background
# "BAUD" bits per second; 10 bits per byte (incl START and STOP bits); plus safety margin
FILESIZE=$(stat -c%s "$2")
TIMEOUT=$(( (FILESIZE / (BAUD/10)) + 10 ))

# some USB-serial adapters (e.g. CH340) corrupt/drop bytes under a single
# continuous burst at low baud rates; sending in small throttled chunks
# avoids this while adding negligible time to the transfer
CHUNK=16
CHUNK_DELAY=0.01

# setup serial port
printf "Opening serial port ($1)... "
timeout 1 cat $1 > /dev/null 2>&1 || true # drain any stale buffered input
stty -F $1 $BAUD raw -echo cs8 -cstopb -ixon clocal cread
exec 3<>$1
printf "OK\n"

# send executable
printf "Uploading executable ($FILESIZE bytes)... "
printf " u" >&3 # skip auto-boot (SPACE) and start upload ('u')
NCHUNKS=$(( (FILESIZE + CHUNK - 1) / CHUNK ))
for ((i=0; i<NCHUNKS; i++)); do
  dd if="$2" bs=$CHUNK skip=$i count=1 2>/dev/null >&3
  sleep $CHUNK_DELAY
done

# wait for upload to complete and check bootloader response
RESPONSE_FILE=$(mktemp)
timeout "$TIMEOUT" cat <&3 > "$RESPONSE_FILE" || true
BUFFER=$(cat "$RESPONSE_FILE")
rm -f "$RESPONSE_FILE"

if [[ "$BUFFER" == *"OK"* ]]; then
  UPOLOAD_OK=1
  printf "OK\n" >&2
elif [ -n "$BUFFER" ]; then
  UPOLOAD_OK=-1
  printf "\nERROR! Invalid bootloader response.\n" >&2
  printf "DEBUG raw response:\n" >&2
  printf '%s' "$BUFFER" | xxd >&2
else
  UPOLOAD_OK=0
  printf "\nERROR! Bootloader response timeout ($TIMEOUT seconds).\n" >&2
fi

# start executable
if [ $UPOLOAD_OK -eq 1 ]; then
  printf "Booting executable...\n"
  printf "e" >&3
fi

# done
exec 3>&-
if [ $UPOLOAD_OK -eq 1 ]; then
  exit 0
else
  printf "Check configuration, reset processor and try again.\n" >&2
  exit 1;
fi
