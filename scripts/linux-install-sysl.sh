#!/usr/bin/env bash
#
# Install the sysl compiler from its release tarball.
#
# slate is a sysl program, so a Linux machine needs the Linux sysl before it can build anything here.
# The version is the repository's `sysl-version` file -- the one place that names the compiler a
# release is built with, on every platform -- and nothing else: no environment variable overrides it,
# so a workflow cannot carry a second copy that falls behind. (`package.hocon`'s `sysl` key is the
# FLOOR, the oldest compiler slate builds with; `scripts/check-sysl-version.sh` refuses a
# `sysl-version` behind it, and runs at the end of this script against what was installed.)
#
# Run as root, or under `sudo`. The prefix defaults to `/usr/local`.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
prefix="${1:-/usr/local}"

version=$(tr -d '[:space:]' < "$repo_root/sysl-version")
if [ -z "$version" ]; then
  echo "$repo_root/sysl-version names no sysl version" >&2
  exit 1
fi

case "$(uname -m)" in
  aarch64|arm64) arch=arm64 ;;
  x86_64|amd64)  arch=x86_64 ;;
  *) echo "sysl publishes no Linux tarball for $(uname -m)" >&2; exit 1 ;;
esac

url="https://github.com/sysl-lang/sysl-bootstrap/releases/download/v$version/sysl-$version-linux-$arch.tar.gz"
echo "installing sysl $version ($arch) into $prefix"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
curl -fsSL "$url" -o "$tmp/sysl.tar.gz"

# The tarball IS a prefix -- `bin/` and `share/` at its root -- so it unpacks straight into one.
mkdir -p "$prefix"
tar -xzf "$tmp/sysl.tar.gz" -C "$prefix"

PATH="$prefix/bin:$PATH" "$repo_root/scripts/check-sysl-version.sh"
