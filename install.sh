#!/usr/bin/env bash
#
# Мастер установки AI-ассистента (macOS / Linux).
# OpenCode V2 + Telegram-бот (grinev/opencode-telegram-bot) + Graphiti/FalkorDB.
#
# Использование:
#   ./install.sh                 интерактивная установка
#   ./install.sh --reconfigure   заново спросить все настройки
#   ./install.sh --no-start      только создать .env, не запускать
#   ./install.sh --yes           без вопросов (для автоматизации)
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$ROOT/.env"

YES=0; RECONF=0; NOSTART=0
for arg in "$@"; do
  case "$arg" in
    -y|--yes)         YES=1 ;;
    -r|--reconfigure) RECONF=1 ;;
    --no-start)       NOSTART=1 ;;
    -h|--help)        sed -n '2,12p' "$0"; exit 0 ;;
    *) echo "Неизвестный параметр: $arg" >&2; exit 2 ;;
  esac
done

if [[ -t 1 ]]; then
  C_CYAN=$'\033[36m'; C_GREEN=$'\033[32m'; C_YELLOW=$'\033[33m'
  C_RED=$'\033[31m';  C_GRAY=$'\033[90m';  C_MAG=$'\033[35m'; C_OFF=$'\033[0m'
else
  C_CYAN=; C_GREEN=; C_YELLOW=; C_RED=; C_GRAY=; C_MAG=; C_OFF=
fi

head() { printf '\n%s%s%s\n' "$C_CYAN" "$1" "$C_OFF"; }
ok()   { printf '  [ok]  %s%s%s\n' "$C_GREEN" "$1" "$C_OFF"; }
info() { printf '  [..]  %s%s%s\n' "$C_GRAY" "$1" "$C_OFF"; }
warn() { printf '  [!!]  %s%s%s\n' "$C_YELLOW" "$1" "$C_OFF" >&2; }
fail() { printf '  [xx]  %s%s%s\n' "$C_RED" "$1" "$C_OFF" >&2; }

ask_value() { # prompt default required(0/1) -> stdout
  local prompt="$1" current="${2:-}" required="${3:-0}" v hint=""
  if [[ $YES -eq 1 ]]; then
    if [[ $required -eq 1 && -z "$current" ]]; then fail "Не задано: $prompt"; exit 1; fi
    printf '%s' "$current"; return
  fi
  [[ -n "$current" ]] && hint=" [$current]"
  read -r -p "$prompt$hint: " v < /dev/tty
  if [[ -z "$v" ]]; then
    if [[ -n "$current" ]]; then printf '%s' "$current"; return; fi
    if [[ $required -eq 1 ]]; then warn 'Обязательное поле, повторите.'; ask_value "$prompt" "$current" "$required"; return; fi
    printf ''; return
  fi
  printf '%s' "$v"
}

ask_secret() { # prompt default required(0/1) -> stdout
  local prompt="$1" current="${2:-}" required="${3:-0}" v hint=""
  if [[ $YES -eq 1 ]]; then
    if [[ $required -eq 1 && -z "$current" ]]; then fail "Не задан секрет: $prompt"; exit 1; fi
    printf '%s' "$current"; return
  fi
  [[ -n "$current" ]] && hint="  (Enter — оставить текущий)"
  printf '%s%s\n' "$prompt" "$hint" >&2
  read -r -s -p "> " v < /dev/tty; printf '\n' >&2
  if [[ -z "$v" ]]; then
    if [[ -n "$current" ]]; then printf '%s' "$current"; return; fi
    if [[ $required -eq 1 ]]; then warn 'Обязательное поле, повторите.'; ask_secret "$prompt" "$current" "$required"; return; fi
    printf ''; return
  fi
  printf '%s' "$v"
}

gen_hex() { openssl rand -hex "${1:-24}" 2>/dev/null || head -c "${1:-24}" /dev/urandom | od -An -tx1 | tr -d ' \n'; }

declare -A D=(
  [TELEGRAM_BOT_TOKEN]="" [TELEGRAM_ALLOWED_USER_ID]="" [BOT_LOCALE]="ru"
  [OPENCODE_SERVER_VERSION]="v2" [OPENCODE_API_URL]="http://opencode:49374"
  [OPENCODE_SERVER_USERNAME]="opencode" [OPENCODE_SERVER_PASSWORD]=""
  [OPENCODE_MODEL_PROVIDER]="openai" [OPENCODE_MODEL_ID]="gpt-4o-mini"
  [OPENAI_API_KEY]="" [ANTHROPIC_API_KEY]="" [OPENROUTER_API_KEY]=""
  [STT_API_URL]="https://api.openai.com/v1" [STT_API_KEY]="" [STT_MODEL]="whisper-1" [STT_LANGUAGE]="ru"
  [COMPOSE_PROFILES]="memory"
  [FALKORDB_PASSWORD]=""
  [GRAPHITI_IMAGE]="ghcr.io/your-github-user/ai-assistant-graphiti:latest" [FALKORDB_IMAGE]="falkordb/falkordb:latest"
  [OPENCODE_IMAGE]="opencode-v2:local" [BOT_IMAGE]="opencode-telegram-bot:local"
  [TZ]="Europe/Moscow" [LOG_LEVEL]="info"
)

if [[ -f "$ENV_FILE" && $RECONF -eq 0 ]]; then
  info "Найдены прежние настройки в .env — значения подставлены, Enter = оставить."
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ "$line" =~ ^[[:space:]]*# ]] && continue
    [[ "$line" != *=* ]] && continue
    key="${line%%=*}"; val="${line#*=}"
    key="$(echo "$key" | xargs)"; val="$(echo "$val" | xargs)"
    [[ -n "$val" && -v "D[$key]" ]] && D["$key"]="$val"
  done < "$ENV_FILE"
fi

save_env() {
  umask 077
  cat > "$ENV_FILE" <<EOF
# ============================================================
#  AI-ассистент  (OpenCode V2 + Telegram-бот + Graphiti/FalkorDB)
#  Создано мастером установки. НЕ коммитьте в git.
# ============================================================

# --- Telegram ---
TELEGRAM_BOT_TOKEN=${D[TELEGRAM_BOT_TOKEN]}
TELEGRAM_ALLOWED_USER_ID=${D[TELEGRAM_ALLOWED_USER_ID]}
BOT_LOCALE=${D[BOT_LOCALE]}

# --- OpenCode Server V2 ---
OPENCODE_SERVER_VERSION=${D[OPENCODE_SERVER_VERSION]}
OPENCODE_API_URL=${D[OPENCODE_API_URL]}
OPENCODE_SERVER_USERNAME=${D[OPENCODE_SERVER_USERNAME]}
OPENCODE_SERVER_PASSWORD=${D[OPENCODE_SERVER_PASSWORD]}

# --- Модель OpenCode ---
OPENCODE_MODEL_PROVIDER=${D[OPENCODE_MODEL_PROVIDER]}
OPENCODE_MODEL_ID=${D[OPENCODE_MODEL_ID]}

# --- Ключи провайдеров ---
OPENAI_API_KEY=${D[OPENAI_API_KEY]}
ANTHROPIC_API_KEY=${D[ANTHROPIC_API_KEY]}
OPENROUTER_API_KEY=${D[OPENROUTER_API_KEY]}

# --- Google Developers API (общий ключ, https://console.cloud.google.com) ---
GOOGLE_API_KEY=

# --- Голос: STT (Whisper-совместимый) ---
STT_API_URL=${D[STT_API_URL]}
STT_API_KEY=${D[STT_API_KEY]}
STT_MODEL=${D[STT_MODEL]}
STT_LANGUAGE=${D[STT_LANGUAGE]}

# --- Память: Graphiti + FalkorDB ---
# Профиль compose: memory включает память. Пусто - без памяти.
COMPOSE_PROFILES=${D[COMPOSE_PROFILES]}
FALKORDB_PASSWORD=${D[FALKORDB_PASSWORD]}
GRAPHITI_IMAGE=${D[GRAPHITI_IMAGE]}
FALKORDB_IMAGE=${D[FALKORDB_IMAGE]}

# --- Docker-образы ---
OPENCODE_IMAGE=${D[OPENCODE_IMAGE]}
BOT_IMAGE=${D[BOT_IMAGE]}

# --- Прочее ---
TZ=${D[TZ]}
LOG_LEVEL=${D[LOG_LEVEL]}
EOF
  ok "Настройки сохранены в $ENV_FILE"
}

printf '%s' "$C_MAG"
cat <<'BANNER'

============================================================
          AI-ассистент  -  мастер установки
     OpenCode V2  +  Telegram-бот  +  Graphiti/FalkorDB
============================================================
BANNER
printf '%s' "$C_OFF"

head '1. Проверка Docker'
if ! command -v docker >/dev/null 2>&1; then
  fail 'Docker не найден.'; info 'Установите: https://docs.docker.com/engine/install/'; exit 1
fi
if ! docker info >/dev/null 2>&1; then fail 'Docker установлен, но не запущен.'; exit 1; fi
if ! docker compose version >/dev/null 2>&1; then fail 'Не найден плагин "docker compose" (v2).'; exit 1; fi
ok 'Docker и docker compose готовы'

head '2. Telegram'
D[TELEGRAM_BOT_TOKEN]="$(ask_secret 'Токен бота (от @BotFather)' "${D[TELEGRAM_BOT_TOKEN]}" 1)"
D[TELEGRAM_ALLOWED_USER_ID]="$(ask_value 'Ваш числовой Telegram ID (от @userinfobot)' "${D[TELEGRAM_ALLOWED_USER_ID]}" 1)"
D[BOT_LOCALE]="$(ask_value 'Язык интерфейса бота (ru|en|...)' "${D[BOT_LOCALE]}")"

head '3. Модель OpenCode'
if [[ $YES -eq 0 ]]; then
  echo 'Выберите провайдера (ключ вводится вручную):'
  echo '   1) OpenAI'
  echo '   2) OpenRouter'
  echo '   3) Anthropic'
  echo '   4) Ollama (локально)'
  echo '   5) Свой вариант'
  while :; do
    read -r -p 'Номер [1]: ' p < /dev/tty
    case "${p:-1}" in
      1) D[OPENCODE_MODEL_PROVIDER]=openai;     D[OPENCODE_MODEL_ID]=gpt-4o-mini; KEYENV=OPENAI_API_KEY;     STTDEF=http://x ;;
      2) D[OPENCODE_MODEL_PROVIDER]=openrouter; D[OPENCODE_MODEL_ID]=openai/gpt-4o-mini; KEYENV=OPENROUTER_API_KEY; STTDEF=http://x ;;
      3) D[OPENCODE_MODEL_PROVIDER]=anthropic;  D[OPENCODE_MODEL_ID]=claude-3-5-sonnet-latest; KEYENV=ANTHROPIC_API_KEY; STTDEF=http://x ;;
      4) D[OPENCODE_MODEL_PROVIDER]=ollama;     D[OPENCODE_MODEL_ID]=llama3.1; KEYENV=""; STTDEF=http://x ;;
      5) D[OPENCODE_MODEL_PROVIDER]=custom;     KEYENV=OPENAI_API_KEY; STTDEF=http://x ;;
      *) warn 'Введите номер из списка.'; continue ;;
    esac
    break
  done
else
  case "${D[OPENCODE_MODEL_PROVIDER]}" in
    openrouter) KEYENV=OPENROUTER_API_KEY ;;
    anthropic)  KEYENV=ANTHROPIC_API_KEY ;;
    ollama)     KEYENV="" ;;
    *)          KEYENV=OPENAI_API_KEY ;;
  esac
fi

D[OPENCODE_MODEL_ID]="$(ask_value 'Модель (provider/model -> model)' "${D[OPENCODE_MODEL_ID]}")"
if [[ -n "${KEYENV:-}" ]]; then
  D[$KEYENV]="$(ask_secret "API-ключ ($KEYENV)" "${D[$KEYENV]:-}" 1)"
fi

head '4. Голос (Whisper-совместимый STT)'
D[STT_API_URL]="$(ask_value 'STT API base URL (пусто — выключить голос)' "${D[STT_API_URL]}")"
if [[ -n "${D[STT_API_URL]}" ]]; then
  stt_default="${D[STT_API_KEY]}"
  [[ -n "$stt_default" ]] || stt_default="${D[${KEYENV:-OPENAI_API_KEY}]:-}"
  D[STT_API_KEY]="$(ask_secret 'STT API-ключ' "$stt_default")"
  D[STT_MODEL]="$(ask_value 'STT модель' "${D[STT_MODEL]}")"
  D[STT_LANGUAGE]="$(ask_value 'Язык распознавания (пусто — авто)' "${D[STT_LANGUAGE]}")"
fi

head '5. Память (Graphiti + FalkorDB)'
if [[ -z "${D[FALKORDB_PASSWORD]}" ]]; then D[FALKORDB_PASSWORD]="$(gen_hex 24)"; ok 'Сгенерирован пароль для FalkorDB.'; fi
D[GRAPHITI_IMAGE]="$(ask_value 'Образ Graphiti MCP' "${D[GRAPHITI_IMAGE]}")"

head '6. Прочее'
if [[ -z "${D[OPENCODE_SERVER_PASSWORD]}" ]]; then D[OPENCODE_SERVER_PASSWORD]="$(gen_hex 24)"; ok 'Сгенерирован пароль для OpenCode Server V2.'; fi
D[TZ]="$(ask_value 'Часовой пояс' "${D[TZ]}")"
D[LOG_LEVEL]="$(ask_value 'Уровень логов (debug|info|warn|error)' "${D[LOG_LEVEL]}")"

save_env

if [[ $NOSTART -eq 1 ]]; then
  head 'Готово'; info 'Запуск пропущен (--no-start). Когда будете готовы:  docker compose up -d --build'; exit 0
fi

head '7. Сборка и запуск контейнеров'
cd "$ROOT"
info 'docker compose up -d --build (первый запуск собирает образы, это долго) ...'
docker compose up -d --build || { fail 'Не удалось запустить. Логи: docker compose logs -f'; exit 1; }
sleep 3
docker compose ps

echo
ok 'Готово!'
info 'Логи:     docker compose logs -f'
info 'Стоп:     docker compose down'
info 'Обновить: docker compose pull && docker compose up -d --build'
