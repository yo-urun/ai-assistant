#!/usr/bin/env bash
#
# Проверка, что локальные патчи бота (bot/patches/*.patch) применяются к
# пин-тегу апстрима (ARG BOT_REF в bot/Dockerfile). Гоняется в CI и депс-ботом.
#
# Использование:
#   scripts/check-fork-patches.sh
#
set -euo pipefail

cd "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

dockerfile="bot/Dockerfile"
ref="$(sed -n 's/^ARG BOT_REF=//p' "$dockerfile" | head -n 1)"
repo="$(sed -n 's/^ARG BOT_REPO=//p' "$dockerfile" | head -n 1)"

if [[ -z "$ref" ]]; then
  echo "!! не найден ARG BOT_REF в ${dockerfile}" >&2
  exit 1
fi
if [[ -z "$repo" ]]; then
  echo "!! не найден ARG BOT_REPO в ${dockerfile}" >&2
  exit 1
fi

shopt -s nullglob
patches=("$PWD"/bot/patches/*.patch)
if [[ ${#patches[@]} -eq 0 ]]; then
  echo "патчей нет — проверять нечего"
  exit 0
fi

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

git -c advice.detachedHead=false init -q "$work"
git -C "$work" remote add origin "$repo"
git -C "$work" fetch -q --depth 1 origin "refs/tags/${ref}"
git -C "$work" checkout -q FETCH_HEAD

for p in "${patches[@]}"; do
  echo "checking $(basename "$p")"
  git -C "$work" apply --check "$p"
done

echo "ok: ${#patches[@]} патч(ей) применяются к ${ref}"
