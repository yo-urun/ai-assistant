# AI-ассистент (базовая сборка)

Готовая обвязка персонального AI-ассистента в Telegram:

- **[OpenCode V2](https://opencode.ai)** — ядро агента: провайдеры, модели,
  сессии, инструменты, MCP, права доступа.
- **[grinev/opencode-telegram-bot](https://github.com/grinev/opencode-telegram-bot)**
  (MIT © Ruslan Grinev) — Telegram-мост: сессии, голос, файлы, команды.
- **Graphiti + FalkorDB** — долговременная память.
- **[opencode-graphiti-extractor](https://github.com/yo-urun/opencode-graphiti-extractor)**
  — фоновый автозахват памяти в Graphiti (без инъекции в контекст); встроен в образ `opencode`.
- **Whisper-совместимый STT** — расшифровка голосовых (уже встроена в бот).

Разворачивается одной командой. Ручной установки Python, баз данных и прочих
зависимостей не требуется — достаточно Docker.

## Возможности

- Мастер установки: `install.ps1` (Windows) и `install.sh` (macOS/Linux) —
  пошагово, со скрытым вводом секретов и генерацией паролей.
- **Серверный деплой** `deploy.sh`: обновление, pull образов, health-wait.
- **CI**: `.github/workflows/images.yml` собирает образы в GHCR (multi-arch).
- **Бэкапы**: `scripts/backup.sh` и `scripts/restore.sh`.
- **systemd-юнит** для автозапуска на VPS.
- Health-check OpenCode, профиль compose `memory` (память можно отключить).
- **Автозахват памяти**: фоновый экстрактор пишет сессии в Graphiti (по завершении
  хода, батчами), с дедупом и durable-очередью. Включён в base-сборку.

## Быстрый старт (локально)

1. Установите [Docker Desktop](https://www.docker.com/products/docker-desktop/)
   (Linux — [Docker Engine + Compose plugin](https://docs.docker.com/engine/install/)).

2. Запустите мастер:

   ```powershell
   .\install.ps1
   ```

   ```bash
   chmod +x install.sh && ./install.sh
   ```

3. Напишите боту в Telegram. Логи: `docker compose logs -f`.

Первый запуск собирает образы (несколько минут). Укажите `GRAPHITI_IMAGE` —
свой рабочий образ памяти, либо отключите память (`COMPOSE_PROFILES=` в `.env`).

## Деплой на VPS

Кратко:

```bash
git clone <ваш-репозиторий> && cd <репозиторий>
chmod +x install.sh deploy.sh scripts/*.sh
./install.sh
./deploy.sh
```

Полное руководство (firewall, готовые образы из GHCR, systemd, бэкапы,
прокси, диагностика) — в **[docs/deploy-vps.md](docs/deploy-vps.md)**.

## Полезные команды

| Действие             | Команда                                              |
|----------------------|------------------------------------------------------|
| Логи                 | `docker compose logs -f`                             |
| Логи OpenCode        | `docker compose logs -f opencode`                    |
| Статус               | `docker compose ps`                                  |
| Остановить           | `docker compose down`                                |
| Обновить (сервер)    | `./deploy.sh`                                        |
| Пересобрать          | `./deploy.sh --build`                                |
| Бэкап / восстановить | `./scripts/backup.sh` · `./scripts/restore.sh <файл>`|

> `docker compose down -v` удаляет тома вместе с данными. Для остановки
> используйте просто `docker compose down`.

## Структура

```
.
├── docker-compose.yml          сервисы: opencode, bot, graphiti, falkordb
├── opencode/
│   ├── Dockerfile              образ OpenCode V2
│   ├── entrypoint.sh           запуск сервера с фиксированным паролем
│   └── opencode.jsonc          модель, агент, права, MCP, плагин-экстрактор
├── bot/Dockerfile              образ Telegram-бота (grinev)
├── install.ps1 / install.sh    мастера установки
├── deploy.sh                   серверный неинтерактивный деплой
├── scripts/backup.sh           бэкап томов
├── scripts/restore.sh          восстановление
├── systemd/ai-assistant.service автозапуск на VPS
├── .github/workflows/images.yml  сборка и публикация образов в GHCR
├── docs/deploy-vps.md          руководство по VPS
├── docs/architecture.md        как всё связано
└── .env.example                шаблон конфигурации
```

## Настройка под себя

- **Модель, права, память** — правьте `opencode/opencode.jsonc`
  (разрешить/запретить инструменты, добавить MCP-серверы), затем
  `docker compose restart opencode`.
- **Сценарии и язык** — через `/settings` прямо в боте.
- **Голос** — ключи `STT_*` в `.env`; озвучка — `TTS_*`.

## Автозахват памяти

В образ `opencode` встроен плагин
[opencode-graphiti-extractor](https://github.com/yo-urun/opencode-graphiti-extractor)
(MIT). Он в фоне (по завершении хода, с дебаунсом) сжимает новую часть сессии и
отправляет её в Graphiti как эпизод — **без инъекции в контекст**, то есть без
добавочных токенов и задержек в обычной работе. Управление — инструментом
`memory` у агента: режимы `search`, `add`, `status`, `redrive`.

Переменные в `.env`:

- `GRAPHITI_URL` — куда писать (по умолчанию `http://graphiti:8000/mcp?codemode=false`);
- `GRAPHITI_GROUP_ID` — группа графа (по умолчанию `main`).

Захват требует профиль `memory` (Graphiti + FalkorDB). Плагин ставится при сборке
образа `opencode` из GitHub — чтобы обновить его, пересоберите образ
(`./deploy.sh --build`).

> Обработку эпизодов (извлечение сущностей/связей) делает сам сервер Graphiti
> асинхронно и, в зависимости от провайдера, не мгновенно.

## Готовые образы (GHCR)

Workflow собирает и публикует `linux/amd64` и `linux/arm64`:

```
ghcr.io/<owner>/<repo>-opencode
ghcr.io/<owner>/<repo>-bot
```

На VPS пропишите их в `.env` (`OPENCODE_IMAGE`, `BOT_IMAGE`) — тогда `deploy.sh`
работает без локальной сборки.

## Границы

Команды бота, которым нужен хостовый файловый доступ — `/open`, `/ls`,
`/worktree`, `/opencode_start`, `/opencode_stop` — в контейнере недоступны.
Для сценария «ассистент» это не критично. Для «кодить с телефона» запускайте
бота на хосте (см. документацию grinev).

## Связанные репозитории

- **[opencode-graphiti-extractor](https://github.com/yo-urun/opencode-graphiti-extractor)**
  — фоновый экстрактор памяти (этот плагин **встроен** в base-сборку выше).
- Сайт проекта: **[takethe.space/ai-assistant](https://takethe.space/ai-assistant)**.

## Лицензии и атрибуция

Сборка **использует и распространяет** сторонние проекты:

- Telegram-бот — [grinev/opencode-telegram-bot](https://github.com/grinev/opencode-telegram-bot),
  **MIT © Ruslan Grinev**. Текст лицензии положите в
  `licenses/opencode-telegram-bot.LICENSE` (ссылка в `licenses/README.md`).
- OpenCode — [anomalyco/opencode](https://github.com/anomalyco/opencode).
- Экстрактор памяти — [yo-urun/opencode-graphiti-extractor](https://github.com/yo-urun/opencode-graphiti-extractor), **MIT**.
- Graphiti и FalkorDB — под своими лицензиями.

Код обвязки в этом репозитории (compose, скрипты, конфиг) — под MIT (`LICENSE`).
