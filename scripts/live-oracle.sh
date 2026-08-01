#!/usr/bin/env bash
# Lane 2 entry point — live-host oracle. Its own CI job on both platforms
# (.github/workflows/ci.yml), after the hermetic build.
#
# Builds (or reuses) the nix-packaged osfacts, then runs the cucumber scenarios
# against a real, noisy host. Diffs answers against `ss` (linux) or `lsof`
# (darwin). Exit non-zero on structural disagreement after one re-sample —
# honest red for the attended run, no exit-0 wrapper.
#
# Usage:
#   ./scripts/live-oracle.sh
#   OSFACTS_BIN=/path/to/osfacts ./scripts/live-oracle.sh

set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

if [[ -z "${OSFACTS_BIN:-}" ]]; then
  echo "live-oracle: nix build .#osfacts …" >&2
  out="$(nix build "$root"#osfacts --no-link --print-out-paths)"
  export OSFACTS_BIN="$out/bin/osfacts"
fi
echo "live-oracle: binary=$OSFACTS_BIN" >&2
"$OSFACTS_BIN" snapshot --procs >/dev/null  # fail fast if the binary is broken

export OSFACTS_LIVE=1
# cargo test drives the harness=false cucumber binary. Dev-deps come from the
# local Cargo.lock; the hermetic gate is nix/nextest, not this script. The
# toolchain is this flake's devShell — the same pin the package builds against,
# never an ambient cargo/rustc, which can miss link deps (darwin `-liconv`)
# even when `cargo` is on PATH. The devShell's cc wrapper supplies that link
# path, so nothing here sets LIBRARY_PATH or RUSTFLAGS by hand.
echo "live-oracle: cargo test via the flake devShell" >&2
nix develop "$root" -c cargo test --test live_oracle
