#!/usr/bin/env bash
#
# Бэкап данных AI-ассистента (тома compose) в один tar.gz.
#
# Использование:
#   ./scripts/backup.sh [каталог_назначения]
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEST="${1:-$ROOT/backups}"
PROJECT="ai-assistant"
STAMP="$(date +%Y%m%d-%H%M%S)"
VOLUMES=(falkordb_data bot_data opencode_data)

command -v docker >/dev/null 2>&1 || { echo 'Docker не найден.' >&2; exit 1; }
mkdir -p "$DEST"
DEST="$(cd "$DEST" && pwd)"

echo "Бэкап томов проекта '$PROJECT' -> $DEST"

vol_args=()
found=0
for v in "${VOLUMES[@]}"; do
  full="${PROJECT}_${v}"
  if docker volume inspect "$full" >/dev/null 2>&1; then
    vol_args+=( -v "${full}:/volumes/${v}:ro" )
    echo "  - $full"
    found=1
  else
    echo "  ! $full отсутствует — пропускаю"
  fi
done

if [[ $found -eq 0 ]]; then
  echo "Нет томов для бэкапа." >&2
  exit 1
fi

OUT="${DEST}/ai-assistant-${STAMP}.tar.gz"
docker run --rm "${vol_args[@]}" -v "${DEST}:/backup" alpine \
  tar czf "/backup/ai-assistant-${STAMP}.tar.gz" -C /volumes .

echo "Готово: $OUT"
