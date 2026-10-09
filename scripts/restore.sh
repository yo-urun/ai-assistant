#!/usr/bin/env bash
#
# Восстановление данных AI-ассистента из бэкапа.
# ВНИМАНИЕ: останавливает стек и ПЕРЕЗАПИСЫВАЕТ содержимое томов.
#
# Использование:
#   ./scripts/restore.sh <файл-бэкапа.tar.gz>
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ARCHIVE="${1:?Укажите файл бэкапа: ./scripts/restore.sh backups/ai-assistant-YYYYmmdd-HHMMSS.tar.gz}"
ARCHIVE="$(cd "$(dirname "$ARCHIVE")" && pwd)/$(basename "$ARCHIVE")"
[[ -f "$ARCHIVE" ]] || { echo "Файл не найден: $ARCHIVE" >&2; exit 1; }

PROJECT="ai-assistant"
VOLUMES=(falkordb_data bot_data opencode_data)

command -v docker >/dev/null 2>&1 || { echo 'Docker не найден.' >&2; exit 1; }

echo "Останавливаю стек..."
docker compose -f "$ROOT/docker-compose.yml" down

echo "Создаю тома (если отсутствуют) и восстанавливаю данные..."
for v in "${VOLUMES[@]}"; do docker volume create "${PROJECT}_${v}" >/dev/null; done

docker run --rm \
  -v "${PROJECT}_falkordb_data:/volumes/falkordb_data" \
  -v "${PROJECT}_bot_data:/volumes/bot_data" \
  -v "${PROJECT}_opencode_data:/volumes/opencode_data" \
  -v "${ARCHIVE}:/backup.tar.gz:ro" \
  alpine sh -c 'cd /volumes && rm -rf ./* && tar xzf /backup.tar.gz'

echo "Готово. Поднимите стек: ./deploy.sh --no-pull"
