# AI asistent (osnovni paket)

[English](README.en.md) · [Русский](README.md) · **Srpski**

Gotova obloga za ličnog AI asistenta u Telegramu:

- **[OpenCode V2](https://opencode.ai)** — jezgro agenta: provajderi, modeli,
  sesije, alati, MCP, dozvole.
- **[grinev/opencode-telegram-bot](https://github.com/grinev/opencode-telegram-bot)**
  (MIT © Ruslan Grinev) — Telegram most: sesije, glas, fajlovi, komande.
- **Graphiti + FalkorDB** — dugoročna memorija.
- **[opencode-graphiti-extractor](https://github.com/yo-urun/opencode-graphiti-extractor)**
  — pozadinsko snimanje memorije u Graphiti (bez ubacivanja u kontekst); ugrađen u
  `opencode` image.
- **Whisper-kompatibilni STT** — prepis glasa (već ugrađen u bota).

Postavlja se jednom komandom. Ručna instalacija Python-a, baza i ostalih zavisnosti
nije potrebna — dovoljan je Docker.

## Mogućnosti

- Čarobnjaci za instalaciju: `install.ps1` (Windows) i `install.sh` (macOS/Linux) —
  korak po korak, sa skrivenim unosom tajni i generisanjem lozinki.
- **Serverski deploy** `deploy.sh`: ažuriranje, pull slika, čekanje na health.
- **CI**: `.github/workflows/images.yml` pravi slike u GHCR (multi-arch).
- **Rezervne kopije**: `scripts/backup.sh` i `scripts/restore.sh`.
- **systemd unit** za automatsko pokretanje na VPS-u.
- OpenCode health-check, compose profil `memory` (memorija se može isključiti).
- **Automatsko snimanje memorije**: pozadinski ekstraktor upisuje sesije u Graphiti
  (po završetku poteza, u grupama), uz deduplikaciju i trajni red. Uključen u osnovni
  paket.

## Brzi start (lokalno)

1. Instaliraj [Docker Desktop](https://www.docker.com/products/docker-desktop/)
   (Linux — [Docker Engine + Compose plugin](https://docs.docker.com/engine/install/)).

2. Pokreni čarobnjaka:

   ```powershell
   .\install.ps1
   ```

   ```bash
   chmod +x install.sh && ./install.sh
   ```

3. Piši botu na Telegramu. Logovi: `docker compose logs -f`.

Prvo pokretanje pravi slike (nekoliko minuta). Postavi `GRAPHITI_IMAGE` — svoju
radnu sliku memorije, ili isključi memoriju (`COMPOSE_PROFILES=` u `.env`).

## Deploy na VPS

Ukratko:

```bash
git clone <tvoj-repozitorijum> && cd <repozitorijum>
chmod +x install.sh deploy.sh scripts/*.sh
./install.sh
./deploy.sh
```

Potpuni vodič (firewall, gotove GHCR slike, systemd, rezervne kopije, proxy,
dijagnostika) — u **[docs/deploy-vps.md](docs/deploy-vps.md)**.

## Korisne komande

| Radnja               | Komanda                                                |
|----------------------|--------------------------------------------------------|
| Logovi               | `docker compose logs -f`                               |
| OpenCode logovi      | `docker compose logs -f opencode`                      |
| Status               | `docker compose ps`                                    |
| Zaustavi             | `docker compose down`                                  |
| Ažuriraj (server)    | `./deploy.sh`                                          |
| Ponovo izgradi       | `./deploy.sh --build`                                  |
| Backup / vraćanje    | `./scripts/backup.sh` · `./scripts/restore.sh <fajl>`  |

> `docker compose down -v` briše volumene zajedno sa podacima. Za zaustavljanje
> koristi samo `docker compose down`.

## Struktura

```
.
├── docker-compose.yml          servisi: opencode, bot, graphiti, falkordb
├── opencode/
│   ├── Dockerfile              OpenCode V2 image
│   ├── entrypoint.sh           pokreće server sa fiksnom lozinkom
│   └── opencode.jsonc          model, agent, dozvole, MCP, plugin-ekstraktor
├── bot/Dockerfile              Telegram bot image (grinev)
├── install.ps1 / install.sh    čarobnjaci za instalaciju
├── deploy.sh                   neinteraktivni serverski deploy
├── scripts/backup.sh           backup volumena
├── scripts/restore.sh          vraćanje
├── systemd/ai-assistant.service automatsko pokretanje na VPS-u
├── .github/workflows/images.yml  pravljenje i objava slika u GHCR
├── docs/deploy-vps.md          vodič za VPS
├── docs/architecture.md        kako se sve povezuje
└── .env.example                šablon konfiguracije
```

## Prilagođavanje

- **Model, dozvole, memorija** — menjaj `opencode/opencode.jsonc`
  (dozvoli/zabrani alate, dodaj MCP servere), pa `docker compose restart opencode`.
- **Scenariji i jezik** — preko `/settings` direktno u botu.
- **Glas** — `STT_*` ključevi u `.env`; izgovor — `TTS_*`.

## Snimanje memorije

U `opencode` image je ugrađen plugin
[opencode-graphiti-extractor](https://github.com/yo-urun/opencode-graphiti-extractor)
(MIT). U pozadini (po završetku poteza, sa debounce) sažima novi deo sesije i šalje
ga u Graphiti kao epizodu — **bez ubacivanja u kontekst**, tj. bez dodatnih tokena i
kašnjenja u normalnom radu. Upravljanje — alatom `memory` kod agenta: režimi `search`,
`add`, `status`, `redrive`.

Promenljive u `.env`:

- `GRAPHITI_URL` — gde se piše (podrazumevano `http://graphiti:8000/mcp?codemode=false`);
- `GRAPHITI_GROUP_ID` — grupa grafa (podrazumevano `opencode`);
- `GRAPHITI_RECALL` — `off` (podrazumevano, samo snimanje) · `start` · `turn` —
  opciono ubacivanje memorije u kontekst (vidi [docs/memory.md](docs/memory.md)).

Snimanje zahteva profil `memory` (Graphiti + FalkorDB). Plugin se instalira pri
izgradnji `opencode` image-a sa GitHub-a — da ga ažuriraš, ponovo izgradi image
(`./deploy.sh --build`).

> Obrada epizoda (izvlačenje entiteta/veza) radi sam Graphiti server asinhrono i, u
> zavisnosti od provajdera, ne trenutno.

## Gotove slike (GHCR)

Workflow pravi i objavljuje `linux/amd64` i `linux/arm64`:

```
ghcr.io/<owner>/<repo>-opencode
ghcr.io/<owner>/<repo>-bot
```

Na VPS-u ih upiši u `.env` (`OPENCODE_IMAGE`, `BOT_IMAGE`) — tada `deploy.sh` radi
bez lokalne izgradnje.

## Ograničenja

Komande bota kojima je potreban pristup fajl sistemu hosta — `/open`, `/ls`,
`/worktree`, `/opencode_start`, `/opencode_stop` — nisu dostupne u kontejneru.
Za scenario „asistent“ to nije kritično. Za „kodiranje sa telefona“ pokreni bota na
hostu (vidi grinev dokumentaciju).

## Povezani repozitorijumi

- **[opencode-graphiti-extractor](https://github.com/yo-urun/opencode-graphiti-extractor)**
  — pozadinski ekstraktor memorije (ovaj plugin je **ugrađen** u osnovni paket iznad).
- Sajt projekta: **[takethe.space/ai-assistant](https://takethe.space/ai-assistant)**.

## Licence i atribucija

Paket **koristi i distribuira** projekte trećih strana:

- Telegram bot — [grinev/opencode-telegram-bot](https://github.com/grinev/opencode-telegram-bot),
  **MIT © Ruslan Grinev**. Tekst licence stavi u
  `licenses/opencode-telegram-bot.LICENSE` (link u `licenses/README.md`).
- OpenCode — [anomalyco/opencode](https://github.com/anomalyco/opencode).
- Ekstraktor memorije — [yo-urun/opencode-graphiti-extractor](https://github.com/yo-urun/opencode-graphiti-extractor), **MIT**.
- Graphiti i FalkorDB — pod svojim licencama.

Kod obloge u ovom repozitorijumu (compose, skripte, konfig) — pod MIT (`LICENSE`).
