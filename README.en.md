# AI assistant and coding agent in Telegram (open self-hosted kit)

**English** · [Русский](README.md) · [Srpski](README.sr.md)

**This is not a product — it is an open base kit.** Use it for yourself, for a
client, or fork it. MIT.

The kit turns [OpenCode](https://opencode.ai) V2 into your personal AI assistant
**and** coding agent, driven straight from Telegram — including from your phone.
Docker is all you need.

What is inside:

- **[OpenCode V2](https://opencode.ai)** — the agent core: providers, models,
  sessions, tools, MCP, permissions.
- **[grinev/opencode-telegram-bot](https://github.com/grinev/opencode-telegram-bot)**
  (MIT © Ruslan Grinev) — the Telegram bridge: sessions, voice, files, commands.
- **Graphiti + FalkorDB** — long-term memory.
- **[opencode-graphiti-extractor](https://github.com/yo-urun/opencode-graphiti-extractor)**
  — background memory capture into Graphiti (no context injection); bundled into
  the `opencode` image.
- **Whisper-compatible STT** — voice transcription (already built into the bot).

Deployed with a single command. No manual installation of Python, databases or
other dependencies — Docker is enough.

> The kit grew out of a personal setup: the agent built itself while the author
> was on the couch with a phone. On the computer, only the Telegram bridge
> (grinev) had to be installed.

## Features

- Install wizards: `install.ps1` (Windows) and `install.sh` (macOS/Linux) —
  step by step, with hidden secret input and password generation.
- **Server deploy** `deploy.sh`: update, pull images, health-wait.
- **CI**: `.github/workflows/images.yml` builds images to GHCR (multi-arch).
- **Backups**: `scripts/backup.sh` and `scripts/restore.sh`.
- **systemd unit** for autostart on a VPS.
- OpenCode health-check, compose profile `memory` (memory can be disabled).
- **Automatic memory capture**: a background extractor writes sessions into
  Graphiti (on turn completion, in batches), with dedup and a durable queue.
  Included in the base kit.
- **Assistant and coder in one**: pick the agent from the bot's keyboard —
  `assistant` for chat (no file edits), the built-in `build` for coding,
  `plan` for read-only planning.
- **Code from your phone**: set `WORKSPACE_DIR` in `.env` and the agent edits
  real files on your disk instead of an isolated volume.

## Quick start (local)

1. Install [Docker Desktop](https://www.docker.com/products/docker-desktop/)
   (Linux — [Docker Engine + Compose plugin](https://docs.docker.com/engine/install/)).

2. Run the wizard:

   ```powershell
   .\install.ps1
   ```

   ```bash
   chmod +x install.sh && ./install.sh
   ```

3. Message your bot on Telegram. Logs: `docker compose logs -f`.

The first run builds the images (a few minutes). Set `GRAPHITI_IMAGE` — your
working memory image, or disable memory (`COMPOSE_PROFILES=` in `.env`).

## VPS deployment

In short:

```bash
git clone <your-repository> && cd <repository>
chmod +x install.sh deploy.sh scripts/*.sh
./install.sh
./deploy.sh
```

Full guide (firewall, prebuilt GHCR images, systemd, backups, proxy, diagnostics)
— in **[docs/deploy-vps.md](docs/deploy-vps.md)**.

## Useful commands

| Action               | Command                                              |
|----------------------|------------------------------------------------------|
| Logs                 | `docker compose logs -f`                             |
| OpenCode logs        | `docker compose logs -f opencode`                    |
| Status               | `docker compose ps`                                  |
| Stop                 | `docker compose down`                                |
| Update (server)      | `./deploy.sh`                                        |
| Rebuild              | `./deploy.sh --build`                                |
| Backup / restore     | `./scripts/backup.sh` · `./scripts/restore.sh <file>`|

> `docker compose down -v` removes volumes together with the data. To stop,
> just use `docker compose down`.

## Structure

```
.
├── docker-compose.yml          services: opencode, bot, graphiti, falkordb
├── opencode/
│   ├── Dockerfile              OpenCode V2 image
│   ├── entrypoint.sh           starts the server with a fixed password
│   └── opencode.jsonc          model, agents, permissions, MCP, extractor plugin
├── bot/Dockerfile              Telegram bot image (grinev)
├── install.ps1 / install.sh    install wizards
├── deploy.sh                   non-interactive server deploy
├── scripts/backup.sh           volume backup
├── scripts/restore.sh          restore
├── systemd/ai-assistant.service autostart on a VPS
├── .github/workflows/images.yml  build and publish images to GHCR
├── docs/deploy-vps.md          VPS guide
├── docs/architecture.md        how it all fits together
└── .env.example                configuration template
```

## Customization

- **Model, agents, permissions, memory** — edit `opencode/opencode.jsonc`
  (agents and their permissions, allow/deny tools, add MCP servers), then
  `docker compose restart opencode`.
- **Code from your phone** — `WORKSPACE_DIR` in `.env` (absolute path to your
  code folder, forward slashes). Empty means an isolated `/workspace` volume.
- **Scenarios and language** — via `/settings` right in the bot.
- **Voice** — `STT_*` keys in `.env`; speech output — `TTS_*`.

## Memory capture

The `opencode` image bundles the
[opencode-graphiti-extractor](https://github.com/yo-urun/opencode-graphiti-extractor)
plugin (MIT). In the background (on turn completion, debounced) it compacts the new
part of the session and sends it to Graphiti as an episode — **without context
injection**, i.e. with no extra tokens or latency in normal work. Control is via the
agent's `memory` tool: modes `search`, `add`, `status`, `redrive`.

Variables in `.env`:

- `GRAPHITI_URL` — where to write (default `http://graphiti:8000/mcp?codemode=false`);
- `GRAPHITI_GROUP_ID` — graph group (default `main`).

Capture requires the `memory` profile (Graphiti + FalkorDB). The plugin is installed
when the `opencode` image is built from GitHub — to update it, rebuild the image
(`./deploy.sh --build`).

> Episode processing (entity/relationship extraction) is done by the Graphiti
> server asynchronously and, depending on the provider, not instantly.

## Prebuilt images (GHCR)

The workflow builds and publishes `linux/amd64` and `linux/arm64`:

```
ghcr.io/<owner>/<repo>-opencode
ghcr.io/<owner>/<repo>-bot
```

On a VPS set them in `.env` (`OPENCODE_IMAGE`, `BOT_IMAGE`) — then `deploy.sh`
works without a local build.

## Coding from your phone and limitations

Coding itself goes through the OpenCode API, so it works from the container: you
message the bot, the `build` agent edits files in
`/workspace`, and replies and diffs come back to the chat.

To have the agent edit **your** files instead of an isolated volume, set
`WORKSPACE_DIR` in `.env` to the absolute path of your code folder (forward
slashes, e.g. `C:/Users/me/project`). That folder is mounted at `/workspace`.

Bot commands that need host filesystem access — `/open`, `/ls`, `/worktree`,
`/opencode_start`, `/opencode_stop` — are unavailable in the container. Those are
about file navigation and starting the server, not about coding itself. If you
need them too, run the bot on the host (see the grinev documentation).

## Related repositories

- **[opencode-graphiti-extractor](https://github.com/yo-urun/opencode-graphiti-extractor)**
  — background memory extractor (this plugin is **bundled** into the base kit above).
- Project site: **[takethe.space/ai-assistant](https://takethe.space/ai-assistant)**.

## Licenses and attribution

The kit **uses and distributes** third-party projects:

- Telegram bot — [grinev/opencode-telegram-bot](https://github.com/grinev/opencode-telegram-bot),
  **MIT © Ruslan Grinev**. Put the license text in
  `licenses/opencode-telegram-bot.LICENSE` (link in `licenses/README.md`).
- OpenCode — [anomalyco/opencode](https://github.com/anomalyco/opencode).
- Memory extractor — [yo-urun/opencode-graphiti-extractor](https://github.com/yo-urun/opencode-graphiti-extractor), **MIT**.
- Graphiti and FalkorDB — under their own licenses.

The wrapper code in this repository (compose, scripts, config) is under MIT (`LICENSE`).
