#!/usr/bin/env bash
#
# Запуск OpenCode V2 как сервера для бота.
# Пароль фиксируем из OPENCODE_SERVER_PASSWORD, чтобы бот мог авторизоваться.
#
set -euo pipefail

PORT="${OPENCODE_PORT:-49374}"

if [[ -n "${OPENCODE_SERVER_PASSWORD:-}" ]]; then
  opencode service set password "$OPENCODE_SERVER_PASSWORD" >/dev/null 2>&1 || true
fi

echo "opencode: starting on 0.0.0.0:${PORT} (version ${OPENCODE_SERVER_VERSION:-v2})"
exec opencode serve --service --hostname 0.0.0.0 --port "$PORT"
