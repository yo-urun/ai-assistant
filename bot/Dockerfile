# ------------------------------------------------------------
#  Telegram-бот: grinev/opencode-telegram-bot (MIT).
#  Образ содержит ТОЛЬКО бота; OpenCode работает отдельным сервисом.
# ------------------------------------------------------------
FROM node:22-slim

# Версия бота. Пин для воспроизводимости сборки;
# обновляется deps-ботом (scripts/deps-bump.sh, PR в develop).
ARG BOT_VERSION=0.26.3
RUN npm install -g "@grinev/opencode-telegram-bot@${BOT_VERSION}"

# Данные бота (settings.json, логи, состояние) — в /data, чтобы жили в volume.
ENV HOME=/data
RUN mkdir -p /data
WORKDIR /data

CMD ["opencode-telegram", "start"]
