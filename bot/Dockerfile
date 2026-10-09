# ------------------------------------------------------------
#  Telegram-бот: grinev/opencode-telegram-bot (MIT).
#  Образ содержит ТОЛЬКО бота; OpenCode работает отдельным сервисом.
# ------------------------------------------------------------
FROM node:22-slim

RUN npm install -g @grinev/opencode-telegram-bot

# Данные бота (settings.json, логи, состояние) — в /data, чтобы жили в volume.
ENV HOME=/data
RUN mkdir -p /data
WORKDIR /data

CMD ["opencode-telegram", "start"]
