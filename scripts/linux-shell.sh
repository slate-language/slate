#!/usr/bin/env bash
#
# A Linux box on a Mac, so that a Linux failure is a minute away rather than a push away.
#
# The development machine is macOS and the release ships Linux tarballs, which means every difference
# between the two -- a `.so` where a `.dylib` was, GNU where BSD was, a kernel that spreads accepted
# connections where the other does not -- is invisible here until CI finds it. This builds the same
# Ubuntu 22.04 the release workflow runs on, with the same `scripts/linux-deps.sh` and the same sysl
# tarball, and drops you in the repo with `sysl build .` and `sysl test .` ready to run.
#
#   scripts/linux-shell.sh              an interactive shell in the container
#   scripts/linux-shell.sh sysl test .  one command, then exit
#
# `SLATE_LINUX_PLATFORM` picks the architecture; it defaults to the host's, which under colima on an
# Apple machine is arm64. `linux/amd64` works too and is emulated, so it is slow but it is the other
# half of the release matrix.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
case "$(uname -m)" in
  arm64|aarch64) host_platform=linux/arm64 ;;
  *)             host_platform=linux/amd64 ;;
esac
platform="${SLATE_LINUX_PLATFORM:-$host_platform}"
image="slate-linux:$(basename "$platform")"

# **The image is built once and reused.** Installing LLVM and a dozen -dev packages takes minutes;
# doing it per run would make the loop this script exists to shorten no shorter than CI.
if ! docker image inspect "$image" >/dev/null 2>&1; then
  echo "building $image for $platform (once; a few minutes)"
  docker build --platform "$platform" -t "$image" -f - "$repo_root" <<'DOCKERFILE'
FROM ubuntu:22.04
COPY scripts/linux-deps.sh /tmp/linux-deps.sh
RUN /tmp/linux-deps.sh && rm -rf /var/lib/apt/lists/* /tmp/linux-deps.sh
ENV PATH=/usr/lib/llvm-20/bin:$PATH
ENV HOME=/home/dev
RUN mkdir -p /home/dev/.cache && chmod -R 777 /home/dev
COPY scripts/linux-install-sysl.sh package.hocon /tmp/sysl/
RUN cd /tmp/sysl && mkdir -p scripts && mv linux-install-sysl.sh scripts/ \
    && scripts/linux-install-sysl.sh /usr/local && rm -rf /tmp/sysl
WORKDIR /src
DOCKERFILE
fi

# **The container runs as the HOST's user, not as root, and that is not only about file ownership.**
# One test makes a directory unreadable and asserts that reading it fails -- and root reads it
# anyway, so a suite run as root reports a defect in the hashing that does not exist. A runner is not
# root either, so this is the arrangement CI has.
#
# **The package cache is a volume, not a layer.** sysl fetches and builds slate's fifteen
# dependencies on the first run; keeping that outside the container means the second run starts where
# the first finished, which is the whole difference between a usable loop and an unusable one.
docker volume create slate-linux-cache >/dev/null

# `--init` so a Ctrl-C reaches the process and a test that leaves a listener behind does not become
# PID 1's orphan. `-t` only where there is a terminal to attach: docker refuses it otherwise, which
# would make the script unusable from a script.
tty_flags=(-i)
[ -t 0 ] && tty_flags=(-i -t)

exec docker run --rm --init "${tty_flags[@]}" \
  --platform "$platform" \
  --user "$(id -u):$(id -g)" \
  -e HOME=/home/dev \
  -v "$repo_root:/src" \
  -v slate-linux-cache:/home/dev/.cache \
  -w /src \
  "$image" \
  "${@:-bash}"
