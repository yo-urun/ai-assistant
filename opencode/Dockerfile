# ------------------------------------------------------------
#  OpenCode V2 server.
# ------------------------------------------------------------
FROM node:22-slim

# Ставим актуальный OpenCode V2 CLI.
RUN npm install -g @opencode/cli

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
# На случай CRLF из Windows — приводим к LF.
RUN sed -i 's/\r$//' /usr/local/bin/entrypoint.sh && chmod +x /usr/local/bin/entrypoint.sh

RUN mkdir -p /workspace
WORKDIR /workspace
EXPOSE 49374

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
