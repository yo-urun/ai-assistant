# Ключи: что, где брать, что обязательно

Короткая шпаргалка для тех, кто разворачивает kit впервые. Все ключи живут
в `.env` (создаётся мастером установки; файл коммитить нельзя).

## Минимум для старта — 2 ключа

| Ключ | Зачем | Где взять |
|---|---|---|
| `TELEGRAM_BOT_TOKEN` | Твой бот в Telegram | [@BotFather](https://t.me/BotFather) → `/newbot` → скопировать токен |
| Ключ LLM-провайдера | Мозг агента | Один из: [platform.openai.com](https://platform.openai.com/api-keys) · [openrouter.ai/keys](https://openrouter.ai/keys) (сотни моделей, дешевле) · [console.anthropic.com](https://console.anthropic.com). Либо без ключа — [Ollama](https://ollama.com) локально |

Ключ LLM кладётся в переменную своего провайдера:

```env
OPENAI_API_KEY=sk-...          # если выбрали OpenAI
OPENROUTER_API_KEY=sk-or-...   # если выбрали OpenRouter
# ANTHROPIC_API_KEY=...        # если выбрали Anthropic
```

Визард установки спросит провайдера и ключ сам. Если меняешь потом — правь
`.env` и `docker compose up -d`.

### Ollama или свой OpenAI-совместимый endpoint

Мастер установки умеет оба варианта:

- **Ollama** — ключ не нужен. Адрес по умолчанию
  `http://host.docker.internal:11434/v1` (Ollama на хосте; `extra_hosts` в
  compose уже добавляет это имя на Linux).
- **Свой endpoint** — `CUSTOM_BASE_URL` (полный URL, обычно с `/v1` на конце)
  и `CUSTOM_API_KEY`.

Эти пункты меню пишут `opencode/opencode.local.jsonc` (в git не попадает) и
ставят `OPENCODE_CONFIG_FILE=opencode.local.jsonc` в `.env`; при возврате на
штатного провайдера переменная снова указывает на `opencode.jsonc`. Почему у
своей модели обязателен `limit` — в [docs/token-budget.md](token-budget.md).

## Модель по умолчанию

`OPENCODE_MODEL_PROVIDER` и `OPENCODE_MODEL_ID` задают, какая модель отвечает.
Примеры: `openai`/`gpt-4o-mini` (дёшево), `openrouter`/`<модель из каталога>`,
`anthropic`/`claude-3-5-sonnet-latest`, `ollama`/`qwen3:8b` (локально).
В `opencode/opencode.jsonc` модель записана ссылкой
`{env:OPENCODE_MODEL_PROVIDER}/{env:OPENCODE_MODEL_ID}`, поэтому `.env` —
единственный источник: правка переменных не требует правки конфига. Можно
менять на лету в боте: `/models`.

## Опциональные ключи

| Ключ | Зачем | Где взять | Без него |
|---|---|---|---|
| `STT_API_KEY` (+ `STT_API_URL`, `STT_MODEL`) | Голосовые сообщения → текст | [console.groq.com/keys](https://console.groq.com/keys) (Whisper бесплатно) или OpenAI | Голос не работает, текст — да |
| `GOOGLE_API_KEY` | Агент сам ходит в Google API (поиск, YouTube) | [Google Cloud Console](https://console.cloud.google.com/apis/credentials) | Просто нет этой функции |
| `OPENAI_BASE_URL` | Прокси/совместимый endpoint вместо api.openai.com (OpenCode) | — | Не нужен большинству |
| `OPENAI_API_URL` | То же для Graphiti; compose берёт `OPENAI_BASE_URL`, если не задан | — | Наследуется из `OPENAI_BASE_URL` |
| `FALKORDB_PASSWORD` | Пароль графовой БД | Генерирует мастер | — |
| `OPENCODE_SERVER_PASSWORD` | Пароль между ботом и агентом | Генерирует мастер | — |

## Память (Graphiti) — что ей нужно

Долговременная память делает эмбеддинги через `OPENAI_API_KEY`
(или `OPENAI_BASE_URL` для совместимых провайдеров). Если выбрал OpenRouter —
задай оба: `OPENROUTER_API_KEY` для модели и `OPENAI_API_KEY` + `OPENAI_BASE_URL=https://openrouter.ai/api/v1` для памяти.

## Правила безопасности

- `.env` никогда не коммитится (уже в `.gitignore`).
- Утёкший ключ — отзвать немедленно у провайдера.
- Для друзей на тест: пусть заводят СВОИ ключи — общий `.env` не пересылай.
