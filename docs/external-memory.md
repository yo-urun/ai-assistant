# Внешняя память: подключение своего Graphiti + FalkorDB

По умолчанию kit поднимает собственные `graphiti` и `falkordb` (профиль
compose `memory`). Если у вас уже есть работающая пара Graphiti MCP +
FalkorDB — kit можно подключить к ней и не плодить второй граф.

## Когда это имеет смысл

- У вас уже накоплена память (узлы/рёбра в графе), и терять её не хочется.
- Эмбеддер в существующем Graphiti настроен нестандартно (например, через
  OpenRouter/совместимый endpoint) — векторы в графе должны считаться тем же
  эмбеддером, что и при поиске, иначе семантический поиск деградирует.

## Как подключить

1. **Не включайте профиль `memory`.** Сервисы `graphiti` и `falkordb`
   стартуют только с ним: оставьте `COMPOSE_PROFILES` пустым (или уберите
   `memory`) в `.env`.

2. **Направьте `GRAPHITI_URL` на ваш Graphiti MCP** в `.env`:

   ```env
   COMPOSE_PROFILES=
   GRAPHITI_URL=http://graphiti-mcp:8000/mcp?codemode=false
   GRAPHITI_GROUP_ID=opencode
   ```

   `GRAPHITI_GROUP_ID` должен совпадать с группой существующего графа —
   иначе экстрактор начнёт писать в отдельное пространство имён.

3. **Соедините сети.** Контейнеры kit'а видят ваш Graphiti, только если он
   в одной docker-сети. После `docker compose up -d`:

   ```bash
   docker network connect ai-assistant_default graphiti-mcp
   docker network connect ai-assistant_default falkordb   # если Graphiti ходит в FalkorDB по имени
   ```

   Альтернатива — опубликовать порт Graphiti на хосте и использовать
   `http://host.docker.internal:<порт>/mcp?codemode=false`.

4. **Ключ эмбеддингов.** Graphiti делает эмбеддинги сам: ваш экземпляр уже
   настроен. Если ваш Graphiti берёт ключ из окружения — он у него уже есть;
   kit'у ключ OpenAI нужен только для самой модели (`OPENAI_API_KEY`).

## Проверка

```bash
docker compose config          # GRAPHITI_URL указывает на внешний сервис
docker compose up -d           # без профиля memory: graphiti/falkordb не стартуют
docker compose ps              # opencode и bot на месте
```

Затем в боте: `/status` — и попросите ассистента вспомнить что-нибудь из
давних разговоров. Ответ «помнит» — значит, внешний граф подхвачен.

## Откат

Хотите вернуться к самодостаточному kit'у — верните `COMPOSE_PROFILES=memory`
и дефолтный `GRAPHITI_URL`, удалите внешние связи сетей. Ваши данные остаются
в томе FalkorDB в любом случае.
