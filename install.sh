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

# --- Провайдер Ollama / свой endpoint ---------------------------------
# Блок providers для opencode.local.jsonc. Адрес берётся из .env
# ({env:...}), limit нужен, чтобы для модели работала компакция.
providers_json() { # kind model context
  case "$1" in
    ollama)
      cat <<JSON
  // Ollama (добавлено мастером установки): адрес — OLLAMA_BASE_URL из .env,
  // limit нужен, чтобы OpenCode вообще включал компакцию для этой модели.
  "providers": {
    "ollama": {
      "settings": { "baseURL": "{env:OLLAMA_BASE_URL}" },
      "models": {
        "$2": {
          "name": "$2",
          "limit": { "context": $3, "output": 8192 }
        }
      }
    }
  },
JSON
      ;;
    custom)
      cat <<JSON
  // Свой OpenAI-совместимый endpoint (добавлено мастером установки):
  // адрес — CUSTOM_BASE_URL, ключ — CUSTOM_API_KEY (оба из .env).
  "providers": {
    "custom": {
      "name": "Custom",
      "env": ["CUSTOM_API_KEY"],
      "package": "@opencode/ai/providers/openai-compatible",
      "settings": { "baseURL": "{env:CUSTOM_BASE_URL}" },
      "models": {
        "$2": {
          "name": "$2",
          "limit": { "context": $3, "output": 8192 }
        }
      }
    }
  },
JSON
      ;;
  esac
}

# opencode.local.jsonc = штатный конфиг, в котором строка-маркер
# «// installer:providers» заменена блоком providers. Так обновления kit'а
# подхватываются: файл пересобирается при каждом запуске мастера.
write_local_config() { # providers-json
  local block="$1" src="$ROOT/opencode/opencode.jsonc" dst="$ROOT/opencode/opencode.local.jsonc"
  if [[ ! -f "$src" ]]; then fail "Не найден $src"; exit 1; fi
  BLOCK="$block" awk '
    /^[[:space:]]*\/\/ installer:providers/ { print ENVIRON["BLOCK"]; next }
    { print }
  ' "$src" > "$dst"
  ok "Конфиг для локального провайдера: opencode/opencode.local.jsonc"
}

valid_model_id() { [[ "$1" =~ ^[A-Za-z0-9._:/-]+$ ]]; }

declare -A D=(
  [TELEGRAM_BOT_TOKEN]="" [TELEGRAM_ALLOWED_USER_ID]="" [BOT_LOCALE]="ru"
  [OPENCODE_SERVER_VERSION]="v2" [OPENCODE_API_URL]="http://opencode:49374"
  [OPENCODE_SERVER_USERNAME]="opencode" [OPENCODE_SERVER_PASSWORD]=""
  [OPENCODE_MODEL_PROVIDER]="openai" [OPENCODE_MODEL_ID]="gpt-4o-mini" [OPENCODE_SMALL_MODEL]=""
  [OPENCODE_CONFIG_FILE]="opencode.jsonc"
  [OLLAMA_BASE_URL]="http://host.docker.internal:11434/v1" [CUSTOM_BASE_URL]=""
  [OPENAI_API_KEY]="" [ANTHROPIC_API_KEY]="" [OPENROUTER_API_KEY]="" [CUSTOM_API_KEY]="" [SELFHOST]="0" [HOST_FS_DIR]=""
  [STT_API_URL]="https://api.groq.com/openai/v1" [STT_API_KEY]="" [STT_MODEL]="whisper-large-v3-turbo" [STT_LANGUAGE]="ru"
  [COMPOSE_PROFILES]="memory"
  [FALKORDB_PASSWORD]=""
  [GRAPHITI_IMAGE]="ghcr.io/your-github-user/ai-assistant-graphiti:latest" [FALKORDB_IMAGE]="falkordb/falkordb:latest"
  [GRAPHITI_MODEL]="gpt-4o-mini" [GRAPHITI_SEMAPHORE_LIMIT]="2" [GRAPHITI_DEBOUNCE_MS]="180000"
  [GRAPHITI_MAX_CHARS]="12000" [GRAPHITI_SEARCH_TOP_K]="5"
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
# Дешёвая модель для сводок компакции (пусто - модель сессии)
OPENCODE_SMALL_MODEL=${D[OPENCODE_SMALL_MODEL]}
# Какой конфиг монтировать: opencode.jsonc | opencode.local.jsonc
OPENCODE_CONFIG_FILE=${D[OPENCODE_CONFIG_FILE]}

# --- Ключи провайдеров ---
OPENAI_API_KEY=${D[OPENAI_API_KEY]}
ANTHROPIC_API_KEY=${D[ANTHROPIC_API_KEY]}
OPENROUTER_API_KEY=${D[OPENROUTER_API_KEY]}
CUSTOM_API_KEY=${D[CUSTOM_API_KEY]}

# --- Локальный провайдер (Ollama / свой endpoint) ---
# Нужны только при OPENCODE_CONFIG_FILE=opencode.local.jsonc.
# Ollama в контейнере — http://ollama:11434/v1, на хосте — host.docker.internal.
OLLAMA_BASE_URL=${D[OLLAMA_BASE_URL]}
CUSTOM_BASE_URL=${D[CUSTOM_BASE_URL]}

# --- Google Developers API (общий ключ, https://console.cloud.google.com) ---
GOOGLE_API_KEY=

# --- Self-support mode (docs/self-support.md) ---
# 1 - агент из контейнера управляет Docker хоста и видит HOST_FS_DIR в /host;
# deploy.sh автоматически подключит docker-compose.selfhost.yml.
SELFHOST=${D[SELFHOST]}
HOST_FS_DIR=${D[HOST_FS_DIR]}

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

# --- Экономия токенов (docs/token-budget.md) ---
GRAPHITI_MODEL=${D[GRAPHITI_MODEL]}
GRAPHITI_SEMAPHORE_LIMIT=${D[GRAPHITI_SEMAPHORE_LIMIT]}
GRAPHITI_DEBOUNCE_MS=${D[GRAPHITI_DEBOUNCE_MS]}
GRAPHITI_MAX_CHARS=${D[GRAPHITI_MAX_CHARS]}
GRAPHITI_SEARCH_TOP_K=${D[GRAPHITI_SEARCH_TOP_K]}

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
  provs=(openai openrouter anthropic ollama custom)
  names=('OpenAI' 'OpenRouter' 'Anthropic' 'Ollama (локально или на хосте)' 'Свой OpenAI-совместимый endpoint')
  defmodels=(gpt-4o-mini openai/gpt-4o-mini claude-3-5-sonnet-latest llama3.1 gpt-4o-mini)
  def=1
  for i in 0 1 2 3 4; do
    [[ "${provs[$i]}" == "${D[OPENCODE_MODEL_PROVIDER]}" ]] && def=$((i + 1))
  done
  echo 'Выберите провайдера:'
  for i in 0 1 2 3 4; do
    mark=' '
    [[ "${provs[$i]}" == "${D[OPENCODE_MODEL_PROVIDER]}" ]] && mark='*'
    printf '   %d) %s %s\n' "$((i + 1))" "$mark" "${names[$i]}"
  done
  while :; do
    read -r -p "Номер [$def]: " p < /dev/tty
    p="${p:-$def}"
    case "$p" in
      1|2|3|4|5)
        idx=$((p - 1))
        D[OPENCODE_MODEL_PROVIDER]="${provs[$idx]}"
        # Явный выбор провайдера — модель сбрасывается на его дефолт.
        # Enter выше оставляет провайдера и модель как были.
        D[OPENCODE_MODEL_ID]="${defmodels[$idx]}"
        break ;;
      *) warn 'Введите номер из списка.' ;;
    esac
  done
fi

PROVIDER_KIND=standard
case "${D[OPENCODE_MODEL_PROVIDER]}" in
  openai)     KEYENV=OPENAI_API_KEY ;;
  openrouter) KEYENV=OPENROUTER_API_KEY ;;
  anthropic)  KEYENV=ANTHROPIC_API_KEY ;;
  ollama)     KEYENV=""; PROVIDER_KIND=ollama ;;
  *)          KEYENV=CUSTOM_API_KEY; PROVIDER_KIND=custom ;;
esac

if [[ "$PROVIDER_KIND" == "standard" ]]; then
  D[OPENCODE_MODEL_ID]="$(ask_value 'Модель (без провайдера, напр. gpt-4o-mini)' "${D[OPENCODE_MODEL_ID]}")"
  D[OPENCODE_CONFIG_FILE]=opencode.jsonc
  if [[ -z "${D[OPENCODE_SMALL_MODEL]}" ]]; then
    case "${D[OPENCODE_MODEL_PROVIDER]}" in
      openai)     D[OPENCODE_SMALL_MODEL]='openai/gpt-4o-mini' ;;
      openrouter) D[OPENCODE_SMALL_MODEL]='openrouter/openai/gpt-4o-mini' ;;
      anthropic)  D[OPENCODE_SMALL_MODEL]='anthropic/claude-3-5-haiku-latest' ;;
    esac
  fi
elif [[ "$PROVIDER_KIND" == "ollama" ]]; then
  D[OPENCODE_MODEL_ID]="$(ask_value 'Модель Ollama (ollama list, напр. qwen3:8b)' "${D[OPENCODE_MODEL_ID]}")"
  valid_model_id "${D[OPENCODE_MODEL_ID]}" || { fail 'В имени модели допустимы буквы, цифры, . _ : / -'; exit 1; }
  D[OLLAMA_BASE_URL]="$(ask_value 'Адрес Ollama, видимый из контейнера (с /v1)' "${D[OLLAMA_BASE_URL]}")"
  ctx="$(ask_value 'Контекст модели, токенов (ollama show <модель>)' 8192)"
  D[OPENCODE_CONFIG_FILE]=opencode.local.jsonc
  write_local_config "$(providers_json ollama "${D[OPENCODE_MODEL_ID]}" "$ctx")"
else
  D[OPENCODE_MODEL_ID]="$(ask_value 'ID модели у провайдера (как в API)' "${D[OPENCODE_MODEL_ID]}")"
  valid_model_id "${D[OPENCODE_MODEL_ID]}" || { fail 'В ID модели допустимы буквы, цифры, . _ : / -'; exit 1; }
  D[CUSTOM_BASE_URL]="$(ask_value 'Base URL endpoint (с /v1 в конце)' "${D[CUSTOM_BASE_URL]}" 1)"
  ctx="$(ask_value 'Контекст модели, токенов' 128000)"
  D[OPENCODE_CONFIG_FILE]=opencode.local.jsonc
  write_local_config "$(providers_json custom "${D[OPENCODE_MODEL_ID]}" "$ctx")"
fi

if [[ -n "${KEYENV:-}" ]]; then
  D[$KEYENV]="$(ask_secret "API-ключ ($KEYENV)" "${D[$KEYENV]:-}" 1)"
fi

head '4. Голос (Whisper-совместимый STT)'
# Пресеты STT; текущий определяем по URL, чтобы повторный запуск
# с Enter ничего не менял.
stt_def=4
case "${D[STT_API_URL]}" in
  "") ;;
  *groq.com*) stt_def=1 ;;
  *api.openai.com*) stt_def=2 ;;
  *) stt_def=3 ;;
esac

if [[ $YES -eq 0 ]]; then
  echo 'Голосовые сообщения (Whisper-совместимый STT):'
  stt_names=(
    'Groq — whisper-large-v3-turbo: быстро, есть бесплатный тариф'
    'OpenAI — whisper-1'
    'Свой OpenAI-совместимый STT'
    'Выключить голос'
  )
  for i in 0 1 2 3; do
    mark=' '; [[ "$((i + 1))" -eq "$stt_def" ]] && mark='*'
    printf '   %d) %s %s\n' "$((i + 1))" "$mark" "${stt_names[$i]}"
  done
  while :; do
    read -r -p "Номер [$stt_def]: " p < /dev/tty
    p="${p:-$stt_def}"
    case "$p" in
      1|2)
        # Ключ прежнего сервиса не подойдёт — забудем, спросим ниже.
        [[ "$p" -eq "$stt_def" ]] || D[STT_API_KEY]=""
        if [[ "$p" -eq 1 ]]; then
          D[STT_API_URL]='https://api.groq.com/openai/v1'
          D[STT_MODEL]='whisper-large-v3-turbo'
        else
          D[STT_API_URL]='https://api.openai.com/v1'
          D[STT_MODEL]='whisper-1'
        fi
        break ;;
      3)
        D[STT_API_URL]="$(ask_value 'STT base URL (OpenAI-совместимый, пусто — выключить голос)' "${D[STT_API_URL]}")"
        [[ -n "${D[STT_API_URL]}" ]] && D[STT_MODEL]="$(ask_value 'STT модель' "${D[STT_MODEL]}")"
        break ;;
      4) D[STT_API_URL]=""; break ;;
      *) warn 'Введите номер из списка.' ;;
    esac
  done
fi

if [[ -n "${D[STT_API_URL]}" ]]; then
  # Ключ Whisper принадлежит STT-сервису: у OpenAI его можно не дублировать
  # (берём OPENAI_API_KEY), для Groq и своих endpoint'ов он свой.
  stt_default="${D[STT_API_KEY]}"
  if [[ -z "$stt_default" && "${D[STT_API_URL]}" == 'https://api.openai.com/v1' ]]; then
    stt_default="${D[OPENAI_API_KEY]:-}"
  fi
  D[STT_API_KEY]="$(ask_secret 'STT API-ключ' "$stt_default")"
  [[ -n "${D[STT_MODEL]}" ]] || D[STT_MODEL]="$(ask_value 'STT модель' whisper-1)"
  D[STT_LANGUAGE]="$(ask_value 'Язык распознавания (пусто — авто)' "${D[STT_LANGUAGE]}")"
  if [[ -z "${D[STT_API_KEY]}" ]]; then
    warn 'STT_API_KEY пуст — голосовые не распознаются. Ключ Groq: https://console.groq.com/keys'
  fi
fi

head '5. Память (Graphiti + FalkorDB)'
if [[ -z "${D[FALKORDB_PASSWORD]}" ]]; then D[FALKORDB_PASSWORD]="$(gen_hex 24)"; ok 'Сгенерирован пароль для FalkorDB.'; fi
D[GRAPHITI_IMAGE]="$(ask_value 'Образ Graphiti MCP' "${D[GRAPHITI_IMAGE]}")"

head '6. Прочее'
if [[ -z "${D[OPENCODE_SERVER_PASSWORD]}" ]]; then D[OPENCODE_SERVER_PASSWORD]="$(gen_hex 24)"; ok 'Сгенерирован пароль для OpenCode Server V2.'; fi
D[SELFHOST]="$(ask_value 'Режим самоподдержки: агент из контейнера управляет Docker хоста и видит папку хоста в /host (1/0)' "${D[SELFHOST]}")"
if [[ "${D[SELFHOST]}" == "1" ]]; then
  D[HOST_FS_DIR]="$(ask_value "Папка хоста, видимая агенту в /host (Enter — домашний каталог)" "${D[HOST_FS_DIR]:-$HOME}")"
fi
D[TZ]="$(ask_value 'Часовой пояс' "${D[TZ]}")"
D[LOG_LEVEL]="$(ask_value 'Уровень логов (debug|info|warn|error)' "${D[LOG_LEVEL]}")"

save_env

if [[ "${D[OPENCODE_CONFIG_FILE]}" == "opencode.local.jsonc" ]]; then
  info 'Провайдер локальный: используется opencode/opencode.local.jsonc (пересобирается при запуске мастера).'
fi

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
