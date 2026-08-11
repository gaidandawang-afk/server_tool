#!/usr/bin/env bash
set -Eeuo pipefail

if (( $# < 2 )); then
  echo "usage: $0 <version-root> <wheel> [<wheel> ...]" >&2
  exit 2
fi

target="${1%/}"
shift

case "$target" in
  /data2/iws/deps/sgl-kernel-npu/*) ;;
  *)
    echo "version-root must be under /data2/iws/deps/sgl-kernel-npu" >&2
    exit 2
    ;;
esac

if [[ "$target" == *"/current" || "$target" == *"/latest" ]]; then
  echo "mutable version pointers are forbidden: $target" >&2
  exit 2
fi

if [[ -e "$target" ]]; then
  echo "version-root already exists; refusing overwrite: $target" >&2
  exit 1
fi

wheels=()
for wheel in "$@"; do
  for expanded in $wheel; do
    [[ -f "$expanded" ]] || { echo "wheel not found: $expanded" >&2; exit 1; }
    wheels+=("$expanded")
  done
done

if (( ${#wheels[@]} == 0 )); then
  echo "no wheels provided" >&2
  exit 2
fi

parent="$(dirname "$target")"
name="$(basename "$target")"
mkdir -p "$parent"
staging="$(mktemp -d "${parent}/.${name}.staging.XXXXXX")"

cleanup() {
  if [[ -d "$staging" ]]; then
    rm -rf -- "$staging"
  fi
}
trap cleanup EXIT

args=(python3 -m pip install --no-deps --target "$staging")
args+=("${wheels[@]}")
"${args[@]}"

{
  printf 'installed_at=%s\n' "$(date --iso-8601=seconds)"
  for wheel in "${wheels[@]}"; do
    printf 'wheel=%s\n' "$wheel"
  done
  find "$staging" -type f -print0 | sort -z | xargs -0 sha256sum
} >"$staging/server-tool-install.txt"

chmod -R a-w "$staging"
mv -- "$staging" "$target"
trap - EXIT
printf 'installed immutable package root: %s (%d wheels)\n' "$target" "${#wheels[@]}"
