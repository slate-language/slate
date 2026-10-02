#!/usr/bin/env bash
#
# Refuse to go on unless the `sysl` on the PATH is the compiler `sysl-version` names.
#
# `sysl-version` is the one place that says which compiler a release is built with: the Linux
# workflows install exactly that version (`scripts/linux-install-sysl.sh`), and the macOS tarball is
# built by whatever `sysl` this machine has. This check is what stops the two drifting apart: the
# release procedure runs it before building the macOS tarball, and the Linux install runs it after
# installing.
#
# `package.hocon`'s `sysl` key is a different number: the FLOOR, the oldest compiler slate builds
# with, which moves only when the language needs it. `sysl-version` may never sit behind it.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

want=$(tr -d '[:space:]' < "$repo_root/sysl-version")
floor=$(grep -oE '^[[:space:]]*sysl[[:space:]]*=[[:space:]]*"[^"]+"' "$repo_root/package.hocon" \
        | head -1 | sed 's/.*"\(.*\)"/\1/')

if [ "$(printf '%s\n%s\n' "$floor" "$want" | sort -V | head -1)" != "$floor" ]; then
  echo "sysl-version says $want, which is behind package.hocon's floor of $floor" >&2
  exit 1
fi

have=$(sysl --version | awk '{print $2}')
if [ "$have" != "$want" ]; then
  echo "the sysl on the PATH is $have, but sysl-version names $want." >&2
  echo "A release is built with one compiler on every platform: install $want, or move" >&2
  echo "sysl-version to $have (a commit on dev) before building." >&2
  exit 1
fi

echo "sysl $have, as sysl-version names (floor $floor)"
