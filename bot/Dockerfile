# ------------------------------------------------------------
#  Telegram-бот: grinev/opencode-telegram-bot (MIT).
#  Собирается из исходников пин-тега + локальных патчей (bot/patches).
#  Образ содержит ТОЛЬКО бота; OpenCode работает отдельным сервисом.
# ------------------------------------------------------------
FROM node:22-slim

# git — клонировать пин-тег и применять патчи; g++/make/python3 — сборка
# нативных зависимостей npm ci.
RUN apt-get update \
    && apt-get install -y --no-install-recommends git ca-certificates python3 make g++ \
    && rm -rf /var/lib/apt/lists/*

# Версия бота = git-тег апстрима. Пин для воспроизводимости сборки;
# обновляется deps-ботом (scripts/deps-bump.sh, PR в develop).
ARG BOT_REPO=https://github.com/grinev/opencode-telegram-bot
ARG BOT_REF=v0.26.3

WORKDIR /src
# Клон пин-тега без истории.
RUN set -eux; \
    git init -q .; \
    git remote add origin "${BOT_REPO}"; \
    git -c advice.detachedHead=false fetch -q --depth 1 origin "refs/tags/${BOT_REF}"; \
    git checkout -q FETCH_HEAD

# Локальные патчи к апстриму (см. bot/patches/README.md).
COPY patches /tmp/patches
RUN set -eux; \
    for p in /tmp/patches/*.patch; do \
      [ -e "$p" ] || continue; \
      echo "applying ${p}"; \
      git apply --verbose "$p"; \
    done; \
    rm -rf /tmp/patches

# Собираем и ставим глобально — bin остаётся `opencode-telegram`, как у npm-версии.
RUN npm ci \
    && npm run build \
    && npm prune --omit=dev \
    && npm install -g .

# Данные бота (settings.json, логи, состояние) — в /data, чтобы жили в volume.
ENV HOME=/data
RUN mkdir -p /data
WORKDIR /data

CMD ["opencode-telegram", "start"]
