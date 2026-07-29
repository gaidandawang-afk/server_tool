#!/usr/bin/env bash
set -Eeuo pipefail

if (( $# < 2 || $# > 3 )); then
  echo "usage: $0 <version-root> <package-spec> [index-url]" >&2
  exit 2
fi

target="${1%/}"
package_spec="$2"
index_url="${3:-}"

case "$target" in
  /data2/iws/deps/*) ;;
  *)
    echo "version-root must be under /data2/iws/deps" >&2
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

args=(python3 -m pip install --no-deps --target "$staging" --report "$staging/install-report.json")
if [[ -n "$index_url" ]]; then
  args+=(--index-url "$index_url")
fi
args+=("$package_spec")
"${args[@]}"

{
  printf 'package_spec=%s\n' "$package_spec"
  printf 'python_abi=%s\n' "$(python3 -c 'import sys; print(f"cp{sys.version_info.major}{sys.version_info.minor}")')"
  printf 'installed_at=%s\n' "$(date --iso-8601=seconds)"
  find "$staging" -type f -print0 | sort -z | xargs -0 sha256sum
} >"$staging/server-tool-install.txt"

chmod -R a-w "$staging"
mv -- "$staging" "$target"
trap - EXIT
printf 'installed immutable package root: %s\n' "$target"
