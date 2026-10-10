#!/usr/bin/env bash
#
# Серверный (VPS) деплой AI-ассистента. Неинтерактивный.
#
# Использование:
#   ./deploy.sh              обновить код, подтянуть образы и поднять стек
#   ./deploy.sh --build      собрать образы на сервере и поднять
#   ./deploy.sh --no-pull    не тянуть образы
#   ./deploy.sh --no-git     не делать git pull
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

BUILD=0; PULL=1; GITPULL=1
for arg in "$@"; do
  case "$arg" in
    --build)   BUILD=1 ;;
    --no-pull) PULL=0 ;;
    --no-git)  GITPULL=0 ;;
    -h|--help) sed -n '2,11p' "$0"; exit 0 ;;
    *) echo "Неизвестный параметр: $arg" >&2; exit 2 ;;
  esac
done

if [[ -t 1 ]]; then
  C_GREEN=$'\033[32m'; C_YELLOW=$'\033[33m'; C_RED=$'\033[31m'; C_GRAY=$'\033[90m'; C_OFF=$'\033[0m'
else
  C_GREEN=; C_YELLOW=; C_RED=; C_GRAY=; C_OFF=
fi
step() { printf '\n==> %s\n' "$1"; }
ok()   { printf '  %s[ok]%s %s\n' "$C_GREEN" "$C_OFF" "$1"; }
info() { printf '  %s[..]%s %s\n' "$C_GRAY" "$C_OFF" "$1"; }
warn() { printf '  %s[!!]%s %s\n' "$C_YELLOW" "$C_OFF" "$1" >&2; }
fail() { printf '  %s[xx]%s %s\n' "$C_RED" "$C_OFF" "$1" >&2; }

get_env() { grep -E "^$1=" "$ROOT/.env" 2>/dev/null | tail -n1 | cut -d= -f2- || true; }

# --- 1. Docker ---
step 'Docker'
command -v docker >/dev/null 2>&1 || { fail 'Docker не найден.'; exit 1; }
if ! docker info >/dev/null 2>&1; then
  fail 'Docker не запущен или нет прав. Добавьте пользователя в группу docker: sudo usermod -aG docker $USER'
  exit 1
fi
docker compose version >/dev/null 2>&1 || { fail 'Нет docker compose v2.'; exit 1; }
ok 'Docker готов'

# --- 2. .env ---
step 'Конфигурация'
[[ -f "$ROOT/.env" ]] || { fail '.env не найден. Сначала запустите ./install.sh'; exit 1; }
chmod 600 "$ROOT/.env" 2>/dev/null || true
ok '.env на месте'

# --- Self-support mode: SELFHOST=1 в .env подключает docker-compose.selfhost.yml ---
DC_ARGS=(-f docker-compose.yml)
if [[ "$(get_env SELFHOST)" == "1" ]]; then
  [[ -f "$ROOT/docker-compose.selfhost.yml" ]] || { fail 'docker-compose.selfhost.yml не найден'; exit 1; }
  DC_ARGS+=(-f docker-compose.selfhost.yml)
  ok 'Self-support mode: ON (агент управляет Docker и видит /host)'
fi

# --- 3. git pull ---
if [[ $GITPULL -eq 1 && -d "$ROOT/.git" ]]; then
  step 'Обновление кода (git)'
  git pull --ff-only || warn 'git pull не удался — продолжаю с текущим кодом'
fi

# --- 4. образы ---
step 'Образы'
OPENCODE_IMAGE="$(get_env OPENCODE_IMAGE)"; OPENCODE_IMAGE="${OPENCODE_IMAGE:-opencode-v2:local}"
BOT_IMAGE="$(get_env BOT_IMAGE)";           BOT_IMAGE="${BOT_IMAGE:-opencode-telegram-bot:local}"
GRAPHITI_IMAGE="$(get_env GRAPHITI_IMAGE)"

if [[ $PULL -eq 1 ]]; then
  info 'docker compose pull ...'
  if docker compose "${DC_ARGS[@]}" pull --ignore-pull-failures; then ok 'pull выполнен'; else warn 'pull с ошибками — при необходимости соберём локально'; BUILD=1; fi
fi

if [[ $BUILD -eq 1 ]] \
   || ! docker image inspect "$OPENCODE_IMAGE" >/dev/null 2>&1 \
   || ! docker image inspect "$BOT_IMAGE" >/dev/null 2>&1; then
  step 'Сборка образов на сервере'
  docker compose "${DC_ARGS[@]}" build opencode bot
fi

# --- 5. проверка образа памяти ---
if grep -qE '^COMPOSE_PROFILES=.*memory' "$ROOT/.env"; then
  step 'Память (Graphiti)'
  if ! docker image inspect "$GRAPHITI_IMAGE" >/dev/null 2>&1; then
    warn "Образ памяти '$GRAPHITI_IMAGE' не найден локально, пробую загрузить..."
    if docker pull "$GRAPHITI_IMAGE" >/dev/null 2>&1 || docker compose "${DC_ARGS[@]}" pull graphiti >/dev/null 2>&1; then
      ok 'Образ памяти загружен'
    else
      fail "Не удалось получить образ памяти '$GRAPHITI_IMAGE'."
      fail "Задайте рабочий GRAPHITI_IMAGE в .env или отключите память строкой: COMPOSE_PROFILES="
      exit 1
    fi
  else
    ok 'Образ памяти на месте'
  fi
fi

# --- 6. запуск ---
step 'Запуск'
docker compose "${DC_ARGS[@]}" up -d --remove-orphans

# --- 7. ожидание OpenCode ---
step 'Ожидание готовности OpenCode'
ready=0
for _ in $(seq 1 30); do
  cid="$(docker compose "${DC_ARGS[@]}" ps -q opencode 2>/dev/null || true)"
  if [[ -n "$cid" ]]; then
    status="$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' "$cid" 2>/dev/null || echo unknown)"
    if [[ "$status" == "healthy" ]]; then ok 'OpenCode готов'; ready=1; break; fi
    if [[ "$status" == "unhealthy" ]]; then fail 'OpenCode unhealthy. Логи: docker compose logs opencode'; break; fi
  fi
  sleep 2
done
[[ $ready -eq 1 ]] || warn 'OpenCode не подтвердил готовность за отведённое время.'

docker compose "${DC_ARGS[@]}" ps

echo
ok 'Деплой завершён'
info 'Логи:  docker compose logs -f'
info 'Стоп:  docker compose down'
