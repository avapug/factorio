#!/bin/bash
set -o pipefail
run() {
  test_bin() {
    command -v "$1" > /dev/null
  }
  get_realpath() {
    echo "$(cd "$(dirname "$1")"; pwd -P)/$(basename "$1")"
  }
  : "${HOST:="https://factoriobox.1au.us"}"
  : "${BENCH_TICKS:=1000}"
  : "${BENCH_RUNS:=5}"
  if [ -z "$FACTORIO_BIN" ]; then
    FACTORIO_BIN=./factorio
    if ! test_bin "$FACTORIO_BIN"; then
      FACTORIO_BIN=factorio
      if ! test_bin "$FACTORIO_BIN"; then
        FACTORIO_BIN=factorio.app/Contents/MacOS/factorio
        if ! test_bin "$FACTORIO_BIN"; then
          FACTORIO_BIN="$HOME/Library/Application Support/Steam/steamapps/common/Factorio/factorio"
          if ! test_bin "$FACTORIO_BIN"; then
            FACTORIO_BIN="/Applications/factorio.app/Contents/MacOS/factorio"
          fi
        fi
      fi
    fi
  fi
  if ! test_bin "$FACTORIO_BIN"; then
    echo "Could not locate the Factorio binary. Validate it is in your path, installed via Steam, or CD to it."
    return 1
  fi
  if ! test_bin stdbuf; then
    echo "stdbuf is not installed. Install it via Homebrew with:"
    echo "brew install coreutils"
    return 1
  fi
  CPU=$(sysctl -n machdep.cpu.brand_string)
  MEMORY=$(($(sysctl -n hw.memsize) / 1024 / 1024))" MB"
  if ! FACTORIO_VERSION=$("$FACTORIO_BIN" --version | head -n 1); then
    echo "Factorio exited with non-zero exit code"
    return 1
  fi
  echo "Found $FACTORIO_VERSION at $(get_realpath "$FACTORIO_BIN")"
  FACTORIO_VERSION_SHORT=$(echo "$FACTORIO_VERSION" | awk '{print $2}')
  : "${URL:="$HOST/map-version/$FACTORIO_VERSION_SHORT"}"
  if [ -z "$MAP" ]; then
    MAP=$(mktemp)
    echo "Downloading map..."
    curl --progress-bar -o "$MAP" "$URL"
  fi
  MAP_HASH=$(sha256sum "$MAP" | awk '{print $1}')
  echo "MAP_HASH=$MAP_HASH"
  echo "Running benchmark..."
  exec 5>&1
  if ! FACTORIO_LOG=$(stdbuf -oL "$FACTORIO_BIN" --mod-directory /dev/null --benchmark "$MAP" --benchmark-ticks "$BENCH_TICKS" --benchmark-runs "$BENCH_RUNS" --benchmark-verbose all --benchmark-sanitize | tee >(grep Performed >&5)) ||
    ! UPS=$(awk -v ticks="$BENCH_TICKS" 'BEGIN{min = -1} $1=="Performed"{if (min == -1 || $5 < min) min = $5} END{print 1000 * ticks / min}' <<< "$FACTORIO_LOG"); then
    echo Benchmark failed
    echo "$FACTORIO_LOG"
    return 1
  fi
  echo "Map benchmarked at $UPS UPS"
  echo "CPU: $CPU"
  echo "Memory: $MEMORY"
  echo "Share your benchmark at: $HOST/result/"$(curl --progress-bar --data-binary @- <<< "v2 mac
$MAP_HASH
$FACTORIO_VERSION
$BENCH_TICKS
$BENCH_RUNS
$(grep -Eo 'Performed \d+ updates in \d+\.\d+ ms' <<< $FACTORIO_LOG)
$(grep "^[^ ]" <<< $FACTORIO_LOG)
$CPU
$MEMORY
$(sysctl -a 2>/dev/null)" -X POST -s -S "$HOST/result")
}
run