#!/usr/bin/env bash
#
# Install the sysl compiler from its release tarball.
#
# slate is a sysl program, so a Linux machine needs the Linux sysl before it can build anything here.
# The version is `package.hocon`'s `sysl` key, which is a FLOOR -- the oldest compiler slate builds
# with -- and it is read from that file rather than written twice, so the two cannot disagree.
#
# Run as root, or under `sudo`. The prefix defaults to `/usr/local`.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
prefix="${1:-/usr/local}"

version="${SYSL_VERSION:-}"
if [ -z "$version" ]; then
  version=$(grep -oE '^[[:space:]]*sysl[[:space:]]*=[[:space:]]*"[^"]+"' "$repo_root/package.hocon" \
            | head -1 | sed 's/.*"\(.*\)"/\1/')
fi
if [ -z "$version" ]; then
  echo "could not read the sysl floor out of $repo_root/package.hocon" >&2
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

"$prefix/bin/sysl" --version
