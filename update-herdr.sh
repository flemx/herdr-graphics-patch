#!/usr/bin/env bash
# Rebuild the installed herdr version with the patches in ./patches and install it.
#
#   ./update-herdr.sh             patch the herdr version that is installed now
#   ./update-herdr.sh --check     only check that the patches apply to that version
#   ./update-herdr.sh --restore   put the official binary back
#
# Options: --version X.Y.Z (build another release), --test (run herdr's graphics tests first).
# Needs: git, rustup (cargo), and Zig 0.16 on PATH or in $ZIG.
# It never stops or restarts herdr. Restart it yourself when it suits you.
set -euo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
WORK=${HERDR_PATCH_WORKDIR:-"$HOME/.cache/herdr-graphics-patch"}
STATE=${HERDR_PATCH_STATE:-"${XDG_STATE_HOME:-$HOME/.local/state}/herdr-graphics-patch"}
UPSTREAM=https://github.com/herdrdev/herdr.git

say() { printf '\033[1m==>\033[0m %s\n' "$*"; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }

mode=install
version=
run_tests=false
while [ $# -gt 0 ]; do
  case "$1" in
    --check) mode=check ;;
    --restore) mode=restore ;;
    --test) run_tests=true ;;
    --version) version=${2:-}; shift ;;
    -h|--help) sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) die "unknown option: $1" ;;
  esac
  shift
done

target=$(command -v herdr || true)
[ -n "$target" ] || die "herdr is not on PATH"
case "$target" in
  /opt/homebrew/*|/usr/local/Cellar/*|/nix/*) die "$target is managed by a package manager; patch a standalone install instead" ;;
esac
mkdir -p "$STATE"
marker="$STATE/installed.sha256"

sha() { shasum -a 256 "$1" | cut -d' ' -f1; }
is_patched() { [ -f "$marker" ] && [ "$(sha "$target")" = "$(cat "$marker")" ]; }

swap_in() {
  local source=$1 tmp
  tmp=$(mktemp "$(dirname "$target")/.herdr-patch.XXXXXX")
  cp "$source" "$tmp"
  chmod 755 "$tmp"
  mv -f "$tmp" "$target"
}

if [ "$mode" = restore ]; then
  backup=$(ls -t "$STATE"/herdr-*.official 2>/dev/null | head -1 || true)
  [ -n "$backup" ] || die "no official backup in $STATE"
  swap_in "$backup"
  rm -f "$marker"
  say "restored $(basename "$backup") to $target"
  say "restart herdr to use it: herdr server stop (ends pane processes), then run herdr"
  exit 0
fi

if [ -z "$version" ]; then
  version=$("$target" --version | awk '{print $2}')
fi
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "could not read a herdr version (got '$version')"
tag="v$version"

if [ "$mode" = install ] && is_patched && [ "$("$target" --version | awk '{print $2}')" = "$version" ]; then
  say "herdr $version at $target is already patched"
  exit 0
fi

command -v git >/dev/null || die "git is required"
src="$WORK/herdr"
if [ ! -d "$src/.git" ]; then
  say "cloning herdr into $src"
  mkdir -p "$WORK"
  git clone --quiet "$UPSTREAM" "$src"
fi
say "checking out $tag"
git -C "$src" fetch --quiet --tags origin
git -C "$src" rev-parse --verify --quiet "refs/tags/$tag" >/dev/null || die "herdr has no tag $tag"
git -C "$src" checkout --quiet --force --detach "$tag"
git -C "$src" clean --quiet -fd

say "applying patches"
for patch in "$HERE"/patches/*.patch; do
  if ! git -C "$src" apply --3way --whitespace=nowarn "$patch"; then
    git -C "$src" reset --quiet --hard "$tag"
    die "$(basename "$patch") does not apply to herdr $version; your installed herdr was not touched"
  fi
done

if [ "$mode" = check ]; then
  git -C "$src" reset --quiet --hard "$tag"
  say "patches apply cleanly to herdr $version"
  exit 0
fi

command -v cargo >/dev/null || die "cargo is required (install rustup: https://rustup.rs)"
zig=${ZIG:-zig}
command -v "$zig" >/dev/null || die "Zig 0.16 is required (put it on PATH or set ZIG)"
case "$("$zig" version)" in 0.16.*) ;; *) die "herdr needs Zig 0.16, found $("$zig" version)" ;; esac
export ZIG="$zig"

if $run_tests; then
  say "running herdr's graphics tests"
  (cd "$src" && cargo test --locked --bin herdr -- --test-threads=1 native_graphics kitty_graphics unix_image_files)
fi

say "building herdr $version (a few minutes the first time)"
(cd "$src" && cargo build --release --locked)
built="$src/target/release/herdr"
[ "$("$built" --version | awk '{print $2}')" = "$version" ] || die "the build reports a different version"

if ! is_patched; then
  backup="$STATE/herdr-$("$target" --version | awk '{print $2}').official"
  cp -p "$target" "$backup"
  say "official binary backed up to $backup"
fi
swap_in "$built"
sha "$target" > "$marker"
say "installed patched herdr $version at $target"
say "restart herdr to use it: herdr server stop (ends pane processes), then run herdr"
say "after a herdr update, run this script again"
