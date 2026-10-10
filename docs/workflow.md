# Процесс разработки и релизов

Короткая модель веток, поток обновлений зависимостей и релизов. Для человека
и для агентов: работаем по ней, а не «как получится».

## Ветки

| Ветка | Назначение | Правила |
|---|---|---|
| `main` | **Продакшн.** То, что ставят пользователи | Только через PR из `develop`. Тег `vX.Y.Z` = релиз |
| `develop` | **Интеграция и тесты.** Сюда падают фичи и deps-PR-ы | PR-ы или аккуратные прямые пуши; CI обязателен |
| `feature/*` | Работа над фичей | От `develop`, PR обратно в `develop` |
| `experiment/*` | Эксперименты (например, `experiment/assistant`) | Мержить только после проверки |
| `hotfix/*` | Срочные фиксы продакшна | От `main`, PR в `main` (+ cherry-pick в `develop`) |
| `deps/*` | Автоматические bumps зависимостей | Создаёт deps-бот, PR в `develop` |

Жизненный цикл фичи: `feature/x` → PR в `develop` → CI зелёный → merge →
когда накопилось достаточно — release-PR `develop` → `main` → тег `vX.Y.Z`.

## Поток обновлений зависимостей

Зависимости **запинены** в Dockerfile-ах (`ARG`), ничего не «плывёт» само:

| Что | Где пин | Откуда берётся новая версия |
|---|---|---|
| OpenCode CLI | `ARG OPENCODE_CLI_VERSION` в `opencode/Dockerfile` | npm `@opencode/cli` |
| Telegram-бот (grinev) | `ARG BOT_VERSION` в `bot/Dockerfile` | npm `@grinev/opencode-telegram-bot` |
| Экстрактор памяти | `ARG EXTRACTOR_REF` в `opencode/Dockerfile` | релизы `yo-urun/opencode-graphiti-extractor` |

Ежедневно (cron) запускается **deps-бот** (`.github/workflows/deps.yml` →
`scripts/deps-bump.sh`): сверяет пины с апстримом и на каждое расхождение
открывает **отдельный PR в `develop`** с описанием, откуда версия и что поменялось.
Дубли PR-ов не создаются: пока PR открыт, повторные запуски его пропускают.

Порядок принятия deps-PR:

1. Открыть PR, посмотреть changelog по ссылке в описании.
2. Merge в `develop` (CI прогонит проверки).
3. Проверить тестовую сборку: образ `ghcr.io/yo-urun/ai-assistant-opencode:develop`
   собирается на каждый пуш в `develop` (workflow `images.yml`).
4. Новая версия уедет в продакшн с ближайшим release-PR.

Проверить расхождения вручную без GitHub-Actions:

```bash
scripts/deps-bump.sh --dry-run
```

## Релиз

1. Убедиться, что `develop` зелёный (CI) и протестирован руками.
2. PR `develop` → `main`, merge.
3. Тег: `git tag vX.Y.Z && git push origin vX.Y.Z`.
4. Автоматика: `images.yml` соберёт и опубликует образы `latest` и `vX.Y.Z`
   в GHCR; `release.yml` создаст GitHub Release с автозаметками.
5. На машине/VPS: `./deploy.sh` — он подтянет свежий код (`git pull`),
   образы (`compose pull`) и перекатит контейнеры (`up -d`).

## Защита веток (настроить один раз в веб-интерфейсе)

Локального `gh` нет, поэтому rulesets ставятся руками:
Settings → Rules → Rulesets → New branch ruleset.

Для `main` (ruleset "production"):
- Bypass list: пусто (или только владелец в крайнем случае).
- Require a pull request before merging: 1 approval (свой аппрув тоже считается,
  если работать с другой ветки/аккаунта; в соло-режиме достаточно самого правила
  «нельзя пушить напрямую»).
- Require status checks: `CI / checks`.
- Block force pushes, Block deletions.

Для `develop` (ruleset "integration"):
- Require status checks: `CI / checks`.
- Block force pushes, Block deletions.

## Локальные проверки (те же, что в CI)

```bash
for f in install.sh deploy.sh scripts/*.sh; do bash -n "$f"; done   # bash
pwsh -c "[System.Management.Automation.Language.Parser]::ParseFile(...)"  # см. ci.yml
node scripts/check-jsonc.mjs opencode/opencode.jsonc                # JSONC
cp .env.example .env && docker compose config > /dev/null && rm .env
```

## Репозиторий экстрактора

`opencode-graphiti-extractor` живёт по той же модели (`main` + релизы-теги).
Пин версии в ai-assistant подтягивается deps-ботом автоматически — вручную
ничего синхронизировать не нужно.
