#!/usr/bin/env bash
#
# Give the runner somewhere to put a heap several times the size of its memory, and make paging into
# it cost as little as it can.
#
# **A swap file alone is not enough, and the measurement is why.** The first run that got past the
# collector's ceiling paged 8.7 million times in an hour and had not finished compiling: at a disk
# fault apiece that is the whole of the wall time, and no deadline makes it finish. So the file is
# fronted by **zswap**, the kernel's compressed cache in front of a swap device -- a page evicted from
# memory is compressed and kept in RAM, and only written to the file when that pool is full.
#
# **zswap rather than a zram device, and the difference is who owns the memory.** A zram swap device
# takes a fixed share of RAM away from the working set whether or not it is holding anything, and
# nothing behind it: a page it cannot take is an allocation failure. zswap's pool is a ceiling rather
# than a reservation, and what it cannot hold goes to the file underneath -- so the worst case is the
# file alone, which is where this started.
#
# Every step of it may fail without failing the build: a kernel with zswap compiled out, or a
# parameter that is read-only at run time, leaves the file doing what it did before.

set -euo pipefail

df -h /mnt /
sudo swapoff -a || true

zswap=/sys/module/zswap/parameters

if [ -d "$zswap" ]; then
  # zstd over zsmalloc is the pairing that holds the most per byte of pool; `max_pool_percent` is the
  # share of RAM the pool may reach before it starts writing through to the file.
  echo zstd     | sudo tee "$zswap/compressor"       > /dev/null || true
  echo zsmalloc | sudo tee "$zswap/zpool"            > /dev/null || true
  echo 40       | sudo tee "$zswap/max_pool_percent" > /dev/null || true
  echo 1        | sudo tee "$zswap/enabled"          > /dev/null || true

  echo "zswap: enabled=$(cat "$zswap/enabled"), $(cat "$zswap/compressor") over $(cat "$zswap/zpool"), up to $(cat "$zswap/max_pool_percent")% of memory"
fi

sudo fallocate -l 48G /mnt/slate-swap
sudo chmod 600 /mnt/slate-swap
sudo mkswap /mnt/slate-swap
sudo swapon /mnt/slate-swap

swapon --show
free -g
