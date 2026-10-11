# Память: модель и самоорганизация

Долговременная память — это **Graphiti** (temporal knowledge graph) поверх
**FalkorDB**, подключённый к агенту как MCP-сервер `graphiti-memory`.
Сервер сам решает почти всё «из коробки»: битемпоральность (`valid_at` /
`invalid_at`), гибридный поиск, провенанс (`MENTIONS`), саги, извлечение
сущностей через LLM. Наша задача — не строить это заново, а **включить,
не ломать и держать в порядке**.

## Слои организации

```
group_id            пространство имён (на FalkorDB = отдельный граф)
  └─ episodes       отдельные записи (сообщения/заметки), провенанс
  └─ saga           упорядоченная нить эпизодов → running summary (summarize_saga)
  └─ entities       сущности (Person, Object, Location, …)
  └─ edges/facts    типизированные связи, с окнами валидности
  └─ communities    кластеры плотно связанных сущностей + саммари (build_communities)
```

«Упорядоченность» — это, по сути, **коммуны** (кластеры) и **саги** (истории),
плюс дисциплина имён на входе. Всё это штатные механизмы Graphiti.

## Что включено в kit

Фоновый экстрактор ([opencode-graphiti-extractor](https://github.com/yo-urun/opencode-graphiti-extractor))
захватывает сессии и пишет эпизоды в Graphiti. С версии **v0.4.0** он также:

| env (`docker-compose.yml`) | смысл | по умолчанию |
|---|---|---|
| `GRAPHITI_UPDATE_COMMUNITIES` | `update_communities=true` при ingest (инкрементальные кластеры) | `false` |
| `GRAPHITI_ORGANIZE_EVERY_HOURS` | периодический `build_communities` (полная перестройка кластеров), `0` — выкл. | `0` |
| `GRAPHITI_SAGA_SCOPE` | `session` — сага на сессию; `project` — общая сага проекта | `session` |
| `GRAPHITI_EXTRACTION_INSTRUCTIONS` | правила каноничного извлечения сущностей/связей | краткое правило из compose |

> ⚠️ **Кластеризация сообществ сейчас выключена намеренно.** В Graphiti
> `build_communities` / `update_communities` зависают на 100% CPU в контейнерном
> деплое (известный баг: [getzep/graphiti#450](https://github.com/getzep/graphiti/issues/450),
> PR #512 «removed community building in MCP»). Поэтому `ORGANIZE_EVERY_HOURS=0`
> и `UPDATE_COMMUNITIES=false`. На MCP-сервере `graphiti-mcp-slim` (graphiti-core
> 0.30.2) баг воспроизводится: прогон вешает сервер на hub-and-spoke графе.
> Включайте эти опции только после апстрим-фикса.

> Самоупорядочивание «работает само»: при включённой кластеризации кластеры
> обновлялись бы при ingest и периодически; сейчас порядок обеспечивают
> **онтология**, **каноничные имена** и **саги** (они не требуют communities).

## Recall: инъекция памяти (опционально)

Захват пишет память, но не гарантирует, что агент её прочитает. С v0.4.0 у
экстрактора есть опциональный **recall** — компактный блок памяти, который
добавляется в контекст модели перед вызовом (через `ctx.session.hook("context")`):

| env | смысл | по умолчанию |
|---|---|---|
| `GRAPHITI_RECALL` | `off` — только захват; `start` — поиск в начале сессии; `turn` — на каждое сообщение | `off` |
| `GRAPHITI_RECALL_MAX_FACTS` | максимум фактов/сущностей в блоке | `5` |
| `GRAPHITI_RECALL_MAX_CHARS` | лимит длины блока | `1200` |
| `GRAPHITI_RECALL_TIMEOUT_MS` | жёсткий таймаут поиска (модель не ждёт Graphiti) | `800` |

По умолчанию `off` — принцип «ноль лишних токенов» сохраняется. Для ассистента
разумный старт — `GRAPHITI_RECALL=start`. Блок дедуплицируется, редактируется от
секретов и ограничен по бюджету; таймауты и ошибки проглатываются, поэтому
недоступный Graphiti не остановит ответ.

## Онтология сервера (`config.yaml`)

Схема сущностей и связей задаётся на стороне Graphiti — в `config.yaml`
(у нас: `~/graphiti-mcp/config.yaml`), ключи `graphiti.entity_types`,
`graphiti.edge_types`, `graphiti.edge_type_map`. Типизированные рёбра
удерживают граф предсказуемым, а коммуны — осмысленными.

## Дисциплина агента

В `agents.assistant.system` прописано: канонические имена сущностей (одно
реальное имя = один узел), приоритет конкретных сущностей над «Topic/Object»,
проверка на дубли перед записью, проактивное сохранение важного.

## Диагностика

- Инструмент ассистента `memory`: `search`, `add`, `status`, `stats`,
  `redrive`, `organize`, `saga`.
- MCP `graphiti-memory`: `search_nodes`, `search_memory_facts`, `get_episodes`,
  `build_communities`, `summarize_saga`, `delete_episode` и др.

## Обслуживание

- **Бэкап**: снапшот тома FalkorDB (`redis-cli BGSAVE` → `dump.rdb`).
- **Разбор дублей/мусора**: `delete_episode` (каскадно) либо точечно в FalkorDB.
- **Перестройка кластеров**: `build_communities` (вручную или по расписанию).
- **Свести графы в один**: на FalkorDB каждый `group_id` — отдельный граф;
  `GRAPHITI_GROUP_ID` экстрактора должен совпадать с рабочим графом, иначе
  память «раздваивается».
