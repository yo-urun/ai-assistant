#!/usr/bin/env bash
#
# deps-бот: сверяет запиненные зависимости с апстримом и открывает PR в develop.
#
# Использование:
#   scripts/deps-bump.sh --dry-run    только показать расхождения (ничего не меняет)
#   scripts/deps-bump.sh              открыть PR-ы для расхождений (нужен gh и право пуша)
#
# Отслеживаемое:
#   @opencode/cli                     -> ARG OPENCODE_CLI_VERSION в opencode/Dockerfile
#   @grinev/opencode-telegram-bot     -> ARG BOT_VERSION в bot/Dockerfile
#   yo-urun/opencode-graphiti-extractor -> ARG EXTRACTOR_REF в opencode/Dockerfile
#
set -euo pipefail

cd "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

BASE_BRANCH="${BASE_BRANCH:-develop}"
DRY_RUN=0
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=1

latest_npm() { npm view "$1" version; }
latest_gh() {
  # gh — в Actions; локально обходимся curl'ом к публичному API.
  if command -v gh >/dev/null 2>&1; then
    gh api "repos/$1/releases/latest" --jq '.tag_name'
  else
    curl -fsSL "https://api.github.com/repos/$1/releases/latest" |
      sed -n 's/.*"tag_name": *"\([^"]*\)".*/\1/p' | head -n 1
  fi
}
current_pin() { sed -n "s/^ARG $1=//p" "$2" | head -n 1; }

# name | file | ARG-переменная | новая версия | старая версия | источник
BUMPS=()

bump() {
  local name="$1" file="$2" var="$3" latest="$4" src="$5"
  local cur
  cur="$(current_pin "$var" "$file")"
  if [[ -z "$cur" ]]; then
    echo "!! ${name}: пин не найден (ARG ${var} в ${file})" >&2
    exit 1
  fi
  if [[ "$cur" == "$latest" ]]; then
    echo "ok  ${name}: ${cur} (актуален)"
    return
  fi
  echo "NEW ${name}: ${cur} -> ${latest}"
  BUMPS+=("${name}|${file}|${var}|${latest}|${cur}|${src}")
}

bump opencode-cli \
  opencode/Dockerfile OPENCODE_CLI_VERSION \
  "$(latest_npm @opencode/cli)" \
  "https://www.npmjs.com/package/@opencode/cli"

bump opencode-telegram-bot \
  bot/Dockerfile BOT_VERSION \
  "$(latest_npm @grinev/opencode-telegram-bot)" \
  "https://www.npmjs.com/package/@grinev/opencode-telegram-bot"

bump graphiti-extractor \
  opencode/Dockerfile EXTRACTOR_REF \
  "$(latest_gh yo-urun/opencode-graphiti-extractor)" \
  "https://github.com/yo-urun/opencode-graphiti-extractor/releases"

if [[ ${#BUMPS[@]} -eq 0 ]]; then
  echo "Все зависимости актуальны."
  exit 0
fi

if [[ "$DRY_RUN" == 1 ]]; then
  echo "dry-run: изменения не применяются и PR не создаются."
  exit 0
fi

git config user.name "deps-bot"
git config user.email "deps-bot@users.noreply.github.com"

for entry in "${BUMPS[@]}"; do
  IFS='|' read -r name file var latest cur src <<<"$entry"
  branch="deps/${name}-${latest#v}"

  # Уже есть открытый PR с этой ветки — не дублируем.
  open_prs="$(gh pr list --head "$branch" --state open --json number -q 'length' 2>/dev/null || echo 0)"
  if [[ "$open_prs" != "0" ]]; then
    echo "PR для ${name} уже открыт — пропускаю."
    continue
  fi

  git fetch origin "$BASE_BRANCH" >/dev/null 2>&1 || true
  git switch -C "$branch" "origin/${BASE_BRANCH}" 2>/dev/null || git switch -C "$branch" "$BASE_BRANCH"

  sed -i "s/^ARG ${var}=.*/ARG ${var}=${latest}/" "$file"
  git add "$file"
  git commit -m "deps: bump ${name} ${cur} -> ${latest}"
  git push -u origin "$branch"

  gh pr create \
    --base "$BASE_BRANCH" \
    --head "$branch" \
    --title "deps: ${name} ${cur} -> ${latest}" \
    --body "Автоматический bump от deps-бота.

- Пин: \`ARG ${var}\` в \`${file}\`
- Было: \`${cur}\` -> Стало: \`${latest}\`
- Источник версий: ${src}

После merge CI прогонит проверки; образы с новой версией соберутся при ближайшем пуше в \`${BASE_BRANCH}\` (workflow \`images.yml\`)."
done
