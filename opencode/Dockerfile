# ------------------------------------------------------------
#  OpenCode V2 server + background memory extractor.
# ------------------------------------------------------------
FROM node:22-slim

# git нужен, чтобы поставить плагин-экстрактор из GitHub при сборке.
RUN apt-get update \
    && apt-get install -y --no-install-recommends git ca-certificates curl \
    && rm -rf /var/lib/apt/lists/*

# Ставим актуальный OpenCode V2 CLI.
ARG OPENCODE_CLI_VERSION=2.2.0
RUN npm install -g "@opencode/cli@${OPENCODE_CLI_VERSION}"

# open-codebase-index: semantic code index (OpenCode native plugin, see docs/code-indexing.md).
# Preinstalled but INERT: activates only per-project via "plugins" config;
# autoIndex is false by default, so the embedder is never called on small projects.
ARG CODE_INDEX_VERSION=0.36.3
RUN npm install -g "open-codebase-index@${CODE_INDEX_VERSION}" \
    && command -v ocbi

# Curated agent skills from mattpocock/skills (MIT), see docs/skills.md.
# Pinned by commit SHA for reproducible builds.
#
# OFF by default: every installed skill adds its name + description to the
# system prompt of *every* request (≈1k tokens per turn). For a personal
# Telegram assistant those engineering skills are dead weight; enable them
# explicitly when you also use the bot for coding:
#   docker build --build-arg INSTALL_SKILLS=true ...
ARG INSTALL_SKILLS=false
ARG SKILLS_REPO=https://github.com/mattpocock/skills
ARG SKILLS_REF=49dd158d1076134a641b33efb035946536778336
RUN set -eux; \
    if [ "${INSTALL_SKILLS}" != "true" ]; then echo "skills: skipped (INSTALL_SKILLS=${INSTALL_SKILLS})"; exit 0; fi; \
    git init -q /tmp/skills \
    && git -C /tmp/skills remote add origin "${SKILLS_REPO}" \
    && git -C /tmp/skills fetch --depth 1 -q origin "${SKILLS_REF}" \
    && git -C /tmp/skills checkout -q FETCH_HEAD; \
    mkdir -p /root/.config/opencode/skills; \
    for s in productivity/grilling productivity/grill-me productivity/handoff \
             productivity/wait-what productivity/writing-for-agents \
             engineering/grill-with-docs engineering/tdd engineering/diagnosing-bugs \
             engineering/code-review engineering/research; do \
      cp -r "/tmp/skills/skills/$s" /root/.config/opencode/skills/; \
    done; \
    rm -rf /tmp/skills; \
    ls /root/.config/opencode/skills

# Docker CLI + compose plugin: self-support mode (see docker-compose.selfhost.yml).
# Pinned; amd64/arm64 via TARGETARCH (static docker downloads use x86_64/aarch64).
ARG DOCKER_CLI_VERSION=29.3.1
ARG DOCKER_COMPOSE_VERSION=5.6.0
ARG TARGETARCH
RUN set -eux; \
    case "${TARGETARCH}" in \
      amd64) DC_ARCH="x86_64" ;; \
      arm64) DC_ARCH="aarch64" ;; \
      *) echo "unsupported TARGETARCH: ${TARGETARCH}" >&2; exit 1 ;; \
    esac; \
    curl -fsSL "https://download.docker.com/linux/static/stable/${DC_ARCH}/docker-${DOCKER_CLI_VERSION}.tgz" \
      | tar xz -C /tmp docker/docker \
      && mv /tmp/docker/docker /usr/local/bin/docker \
      && rm -rf /tmp/docker; \
    mkdir -p /usr/local/lib/docker/cli-plugins; \
    curl -fsSL "https://github.com/docker/compose/releases/download/v${DOCKER_COMPOSE_VERSION}/docker-compose-linux-${DC_ARCH}" \
      -o /usr/local/lib/docker/cli-plugins/docker-compose; \
    chmod +x /usr/local/lib/docker/cli-plugins/docker-compose; \
    docker --version \
    && docker compose version

# uv: runtime for optional MCP servers (Serena code indexing, see docs/code-indexing.md).
# Inert until the MCP server is enabled in config.
ARG UV_VERSION=0.13.0
RUN set -eux; \
    case "${TARGETARCH}" in \
      amd64) UV_ARCH="x86_64" ;; \
      arm64) UV_ARCH="aarch64" ;; \
      *) echo "unsupported TARGETARCH: ${TARGETARCH}" >&2; exit 1 ;; \
    esac; \
    curl -fsSL "https://github.com/astral-sh/uv/releases/download/${UV_VERSION}/uv-${UV_ARCH}-unknown-linux-gnu.tar.gz" \
      | tar xz -C /tmp \
      && mv "/tmp/uv-${UV_ARCH}-unknown-linux-gnu/uv" /usr/local/bin/uv \
      && mv "/tmp/uv-${UV_ARCH}-unknown-linux-gnu/uvx" /usr/local/bin/uvx \
      && rm -rf /tmp/uv-*; \
    uv --version

# Фоновый экстрактор памяти (OpenCode V2 -> Graphiti MCP).
# Плагин не имеет рантайм-зависимостей; читает GRAPHITI_URL / GRAPHITI_GROUP_ID из окружения.
ARG EXTRACTOR_REPO=https://github.com/yo-urun/opencode-graphiti-extractor
ARG EXTRACTOR_REF=v0.5.0
RUN git clone --depth 1 --branch ${EXTRACTOR_REF} ${EXTRACTOR_REPO} /opt/graphiti-extractor

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
# На случай CRLF из Windows — приводим к LF.
RUN sed -i 's/\r$//' /usr/local/bin/entrypoint.sh && chmod +x /usr/local/bin/entrypoint.sh

RUN mkdir -p /workspace
WORKDIR /workspace
EXPOSE 49374

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
