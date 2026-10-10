# Деплой на VPS

Пошаговое руководство для боевого сервера (Ubuntu 22.04/24.04 или другой Linux).

Бот работает через **long polling**, поэтому **входящие порты не нужны**:
ни домена, ни TLS, ни проброса портов. Наружу уходит только трафик к Telegram
и к вашему LLM-провайдеру.

> **Редакции OpenCode:** на VPS нужна только CLI-версия — образ kit'а
> содержит `@opencode/cli` и поднимает серверный режим (`opencode serve`),
> с которым общается бот по API. Десктоп-приложение — необязательная
> GUI-обёртка для работы за монитором; на headless-сервере оно не нужно.

## Требования

| Ресурс | Минимум | Комфортно |
|---|---|---|
| CPU    | 2 vCPU  | 2 vCPU    |
| RAM    | 2 ГБ    | 4 ГБ      |
| Диск   | 20 ГБ   | 30 ГБ+    |
| ОС     | Ubuntu 22.04/24.04 | — |

> На 1 ГБ RAM **сборка образов может упасть по OOM**. Либо возьмите 2 ГБ+,
> либо собирайте образы в CI и ставьте на VPS готовые (см. ниже).

## Быстрый путь (готовые образы из GHCR)

1. Залейте репозиторий на GitHub. Workflow `.github/workflows/images.yml`
   сам соберёт образы и опубликует в GHCR:
   - `ghcr.io/<owner>/<repo>-opencode`
   - `ghcr.io/<owner>/<repo>-bot`

2. На VPS:

```bash
sudo apt update && sudo apt install -y git
git clone https://github.com/<owner>/<repo>.git
cd <repo>
chmod +x install.sh deploy.sh scripts/*.sh
./install.sh          # заполнит .env (токены, ключи, пароли)
```

3. В `.env` пропишите образы из GHCR и **свой** образ памяти:

```env
OPENCODE_IMAGE=ghcr.io/<owner>/<repo>-opencode:latest
BOT_IMAGE=ghcr.io/<owner>/<repo>-bot:latest
GRAPHITI_IMAGE=ghcr.io/<owner>/<repo>-graphiti:latest   # или свой
```

4. Деплой без сборки:

```bash
./deploy.sh
```

`deploy.sh` обновит код (`git pull`), подтянет образы, поднимет стек и
дождётся готовности OpenCode.

## Путь со сборкой на сервере

Если готовых образов нет:

```bash
./deploy.sh --build
```

На слабом VPS добавьте swap:

```bash
sudo fallocate -l 2G /swapfile && sudo chmod 600 /swapfile
sudo mkswap /swapfile && sudo swapon /swapfile
echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
```

## Память (Graphiti) — необязательно

Память включается профилем compose `memory`:

- `.env`: `COMPOSE_PROFILES=memory` — включено;
- `.env`: `COMPOSE_PROFILES=` — выключено (стек поднимется без Graphiti и FalkorDB).

Если включено, `GRAPHITI_IMAGE` **обязан** указывать на рабочий образ,
иначе `deploy.sh` остановится с понятной ошибкой.

## Firewall

Разрешите только SSH (и больше ничего — порты наружу не публикуются):

```bash
sudo ufw allow OpenSSH
sudo ufw enable
sudo ufw status
```

## Автозапуск (systemd)

У сервисов уже стоит `restart: unless-stopped`, а Docker поднимается при
загрузке. Формально закрепить проект:

```bash
sudo cp systemd/ai-assistant.service /etc/systemd/system/
sudo nano /etc/systemd/system/ai-assistant.service   # впишите WorkingDirectory
sudo systemctl daemon-reload
sudo systemctl enable --now ai-assistant
sudo systemctl status ai-assistant
```

## Бэкапы

Тома `falkordb_data`, `bot_data`, `opencode_data` содержат память, настройки
и сессии. Бэкап — одной командой:

```bash
./scripts/backup.sh ./backups
```

Восстановление (останавливает стек и перезаписывает тома):

```bash
./scripts/restore.sh ./backups/ai-assistant-YYYYmmdd-HHMMSS.tar.gz
```

Ежедневный бэкап через cron:

```cron
0 3 * * * cd /opt/ai-assistant && ./scripts/backup.sh ./backups >> ./backups/backup.log 2>&1
```

> Не используйте `docker compose down -v` — флаг `-v` удаляет тома вместе
> с данными. Для остановки достаточно `docker compose down`.

## Обновление

```bash
./deploy.sh                 # pull образов + перезапуск
# или, при сборке на сервере:
./deploy.sh --build
```

## Прокси и блокировки

- Telegram: `TELEGRAM_PROXY_URL` (SOCKS/HTTP) или `TELEGRAM_API_ROOT` в `.env`.
- LLM/STT: переменные `HTTP_PROXY`, `HTTPS_PROXY`, `NO_PROXY` для контейнера
  `opencode` (добавьте в блок `environment` сервиса `opencode`).

## Диагностика

| Проблема | Что проверить |
|---|---|
| «Docker не запущен» | `sudo usermod -aG docker $USER`, перелогин |
| Бот молчит | `docker compose logs -f bot`, верность `TELEGRAM_ALLOWED_USER_ID` |
| «OpenCode server not available» | `docker compose logs opencode`, `OPENCODE_SERVER_PASSWORD` |
| Память не работает | образ `GRAPHITI_IMAGE`, `docker compose logs graphiti` |
| Graphiti: «Missing credentials» | задайте `OPENAI_API_KEY` — Graphiti строит эмбеддинги/реранкер через OpenAI (или свой endpoint через `OPENAI_BASE_URL`) |
| Порт занят | хостовый `opencode` уже слушает 49374 — контейнеру он не нужен |

Проверка API OpenCode вручную (изнутри сети compose):

```bash
docker compose exec opencode opencode api get /api/info
```
