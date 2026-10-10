# ------------------------------------------------------------
#  OpenCode V2 server + background memory extractor.
# ------------------------------------------------------------
FROM node:22-slim

# git нужен, чтобы поставить плагин-экстрактор из GitHub при сборке.
RUN apt-get update \
    && apt-get install -y --no-install-recommends git ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Ставим актуальный OpenCode V2 CLI.
RUN npm install -g @opencode/cli

# Фоновый экстрактор памяти (OpenCode V2 -> Graphiti MCP).
# Плагин не имеет рантайм-зависимостей; читает GRAPHITI_URL / GRAPHITI_GROUP_ID из окружения.
ARG EXTRACTOR_REPO=https://github.com/yo-urun/opencode-graphiti-extractor
ARG EXTRACTOR_REF=v0.2.1
RUN git clone --depth 1 --branch ${EXTRACTOR_REF} ${EXTRACTOR_REPO} /opt/graphiti-extractor

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
# На случай CRLF из Windows — приводим к LF.
RUN sed -i 's/\r$//' /usr/local/bin/entrypoint.sh && chmod +x /usr/local/bin/entrypoint.sh

RUN mkdir -p /workspace
WORKDIR /workspace
EXPOSE 49374

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
