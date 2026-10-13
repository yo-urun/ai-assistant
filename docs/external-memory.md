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

## Вариант: полностью самодостаточный kit с переносом данных

Если цель — один стек в Docker без внешних зависимостей, можно перенести
данные в собственные сервисы kit'а:

1. Остановите старую пару (`docker stop graphiti-mcp falkordb`) — два
   писателя в один том недопустимы.
2. Подключите существующий том данных к `falkordb` из kit'а. Проще всего —
   через `docker-compose.override.yml`:

   ```yaml
   services:
     falkordb:
       volumes:
         - graphiti-falkordb-data:/var/lib/falkordb/data
   volumes:
     graphiti-falkordb-data:
       external: true
   ```

3. **Сойдите эмбеддер.** Векторы в перенесённом графе посчитаны конкретной
   моделью. Поиск сравнивает векторы, поэтому новый Graphiti MCP должен считать
   эмбеддинги **той же** моделью — задайте её в `.env` (или в
   `docker-compose.override.yml`):

   ```yaml
   services:
     graphiti:
       environment:
         EMBEDDER_MODEL: <та-же-модель-эмбеддера>
         OPENAI_API_URL: <OpenAI-совместимый-base-url>
   ```

   (имена переменных зависят от вашей сборки Graphiti MCP — сверьте с её
   документацией/`docker inspect`).

4. `COMPOSE_PROFILES=memory`, `GRAPHITI_URL` — дефолтный (внутренний
   `graphiti`), `GRAPHITI_GROUP_ID` — прежний (`opencode`).

После этого старые контейнеры можно удалить; данные живут в томе, который
теперь обслуживает kit.

## Откат

Хотите вернуться к самодостаточному kit'у — верните `COMPOSE_PROFILES=memory`
и дефолтный `GRAPHITI_URL`, удалите внешние связи сетей. Ваши данные остаются
в томе FalkorDB в любом случае.
