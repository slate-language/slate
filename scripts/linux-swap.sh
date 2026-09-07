#!/usr/bin/env bash
#
# Give the runner somewhere to put a heap several times the size of its memory, and make paging into
# it cost as little as it can.
#
# **Nearly all of a Linux build's wall time is paging, so the interesting question is what a page
# fault costs.** The compile touches some 50 GB against the runner's 15, and pages 8.7 to 10.8
# million times doing it -- at a disk fault apiece that is the whole of the wall clock.
#
# **zswap is the kernel's compressed cache in front of a swap device**, and it is enabled here on the
# theory that a fault served out of a compressed pool in RAM costs a fraction of one served off the
# disk. **On this workload it does almost nothing, which is a finding rather than a defect**: the
# 39:44 arm64 build held 0.1 GB in the pool and wrote 90 GB through it to the file, so the
# collector's pages are not compressing and the disk does the work either way. It is left in place
# because it costs nothing, it cannot make things worse -- what the pool will not take goes to the
# file underneath, which is where this started -- and a compiler that allocates differently later
# would get it for free. `scripts/linux-measure.sh` prints those two numbers on every run, so the
# claim in this paragraph is re-measured rather than trusted.
#
# **zswap rather than a zram device, and the difference is who owns the memory.** A zram swap device
# takes a fixed share of RAM away from the working set whether or not it is holding anything, and
# nothing behind it: a page it cannot take is an allocation failure. zswap's pool is a ceiling rather
# than a reservation, and on the evidence above that ceiling is never reached.
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
