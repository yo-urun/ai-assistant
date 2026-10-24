#Requires -Version 5.1
<#
.SYNOPSIS
    Мастер установки AI-ассистента.
    OpenCode V2 + Telegram-бот (grinev/opencode-telegram-bot) + Graphiti/FalkorDB.

.DESCRIPTION
    Пошагово спрашивает настройки и API-ключи, создаёт .env и запускает
    docker compose. Секреты вводятся скрыто. Повторный запуск не затирает
    уже введённые значения — просто нажимайте Enter.

.EXAMPLE
    .\install.ps1
    .\install.ps1 -Reconfigure   # заново спросить все настройки
    .\install.ps1 -NoStart       # только создать .env, не запускать
    .\install.ps1 -Yes           # без вопросов (для автоматизации)
#>
[CmdletBinding()]
param(
    [switch]$Yes,
    [switch]$Reconfigure,
    [switch]$NoStart
)

$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }
$Root    = Split-Path -Parent $MyInvocation.MyCommand.Path
$EnvFile = Join-Path $Root '.env'

# ------------------------------------------------------------------ вывод
function Write-Head([string]$t) { Write-Host "`n$t" -ForegroundColor Cyan }
function Ok([string]$m)   { Write-Host "  [ok]  $m" -ForegroundColor Green }
function Info([string]$m) { Write-Host "  [..]  $m" -ForegroundColor DarkGray }
function Warn([string]$m) { Write-Host "  [!!]  $m" -ForegroundColor Yellow }
function Fail([string]$m) { Write-Host "  [xx]  $m" -ForegroundColor Red }

# ------------------------------------------------------------------ ввод
function AskValue {
    param([string]$Prompt, [string]$Current = '', [switch]$Required)
    if ($Yes) {
        if ($Required -and [string]::IsNullOrWhiteSpace($Current)) {
            throw "Не задано обязательное поле: $Prompt"
        }
        return $Current
    }
    while ($true) {
        $hint = if ($Current) { " [$Current]" } else { '' }
        $v = Read-Host "$Prompt$hint"
        if ([string]::IsNullOrWhiteSpace($v)) {
            if ($Current) { return $Current }
            if ($Required) { Warn 'Обязательное поле, повторите.'; continue }
            return ''
        }
        return $v.Trim()
    }
}

function AskSecret {
    param([string]$Prompt, [string]$Current = '', [switch]$Required)
    if ($Yes) {
        if ($Required -and [string]::IsNullOrWhiteSpace($Current)) {
            throw "Не задан секрет: $Prompt"
        }
        return $Current
    }
    while ($true) {
        $hint = if ($Current) { '  (Enter — оставить текущий)' } else { '' }
        Write-Host "$Prompt$hint"
        $sec = Read-Host -AsSecureString
        $ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec)
        try { $v = [Runtime.InteropServices.Marshal]::PtrToStringAuto($ptr) }
        finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr) }
        if ([string]::IsNullOrWhiteSpace($v)) {
            if ($Current) { return $Current }
            if ($Required) { Warn 'Обязательное поле, повторите.'; continue }
            return ''
        }
        return $v.Trim()
    }
}

function New-Hex([int]$Bytes = 24) {
    $buf = [byte[]]::new($Bytes)
    [System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($buf)
    ($buf | ForEach-Object { $_.ToString('x2') }) -join ''
}

# -------------------------------------------------- Ollama / свой endpoint
# Блок providers для opencode.local.jsonc. Адрес берётся из .env
# ({env:...}), limit нужен, чтобы для модели работала компакция.
function Get-ProvidersJson([string]$Kind, [string]$Model, [int]$Context) {
    if ($Kind -eq 'ollama') {
        return @"
  // Ollama (добавлено мастером установки): адрес — OLLAMA_BASE_URL из .env,
  // limit нужен, чтобы OpenCode вообще включал компакцию для этой модели.
  "providers": {
    "ollama": {
      "settings": { "baseURL": "{env:OLLAMA_BASE_URL}" },
      "models": {
        "$Model": {
          "name": "$Model",
          "limit": { "context": $Context, "output": 8192 }
        }
      }
    }
  },
"@ -split "`r?`n"
    }
    return @"
  // Свой OpenAI-совместимый endpoint (добавлено мастером установки):
  // адрес — CUSTOM_BASE_URL, ключ — CUSTOM_API_KEY (оба из .env).
  "providers": {
    "custom": {
      "name": "Custom",
      "env": ["CUSTOM_API_KEY"],
      "package": "@opencode/ai/providers/openai-compatible",
      "settings": { "baseURL": "{env:CUSTOM_BASE_URL}" },
      "models": {
        "$Model": {
          "name": "$Model",
          "limit": { "context": $Context, "output": 8192 }
        }
      }
    }
  },
"@ -split "`r?`n"
}

# opencode.local.jsonc = штатный конфиг, в котором строка-маркер
# «// installer:providers» заменена блоком providers. Файл пересобирается
# при каждом запуске мастера, поэтому обновления kit'а подхватываются.
function Write-LocalConfig([string[]]$Block) {
    $src = Join-Path $Root 'opencode\opencode.jsonc'
    $dst = Join-Path $Root 'opencode\opencode.local.jsonc'
    if (-not (Test-Path -LiteralPath $src)) { Fail "Не найден $src"; exit 1 }
    $out = New-Object System.Collections.Generic.List[string]
    $found = $false
    foreach ($line in Get-Content -LiteralPath $src -Encoding UTF8) {
        if ($line -match '^\s*//\s*installer:providers') {
            foreach ($b in $Block) { $out.Add($b) }
            $found = $true
        } else {
            $out.Add($line)
        }
    }
    if (-not $found) { Fail 'В opencode.jsonc нет строки-маркера installer:providers'; exit 1 }
    $enc = New-Object System.Text.UTF8Encoding($false)   # без BOM
    [System.IO.File]::WriteAllLines($dst, $out, $enc)
    Ok 'Конфиг для локального провайдера: opencode\opencode.local.jsonc'
}

# ------------------------------------------------------------------ env
function Read-EnvMap([string]$Path) {
    $map = @{}
    if (-not (Test-Path -LiteralPath $Path)) { return $map }
    foreach ($line in Get-Content -LiteralPath $Path -Encoding UTF8) {
        if ($line -match '^\s*#' -or [string]::IsNullOrWhiteSpace($line)) { continue }
        $i = $line.IndexOf('=')
        if ($i -lt 1) { continue }
        $map[$line.Substring(0, $i).Trim()] = $line.Substring($i + 1).Trim()
    }
    return $map
}

function Save-Env([hashtable]$m) {
    $l = New-Object System.Collections.Generic.List[string]
    $add = { param($s) $l.Add($s) }
    & $add '# ============================================================'
    & $add '#  AI-ассистент  (OpenCode V2 + Telegram-бот + Graphiti/FalkorDB)'
    & $add '#  Создано мастером установки. НЕ коммитьте в git.'
    & $add '# ============================================================'
    & $add ''
    & $add '# --- Telegram ---'
    & $add "TELEGRAM_BOT_TOKEN=$($m.TELEGRAM_BOT_TOKEN)"
    & $add "TELEGRAM_ALLOWED_USER_ID=$($m.TELEGRAM_ALLOWED_USER_ID)"
    & $add "BOT_LOCALE=$($m.BOT_LOCALE)"
    & $add ''
    & $add '# --- OpenCode Server V2 ---'
    & $add "OPENCODE_SERVER_VERSION=$($m.OPENCODE_SERVER_VERSION)"
    & $add "OPENCODE_API_URL=$($m.OPENCODE_API_URL)"
    & $add "OPENCODE_SERVER_USERNAME=$($m.OPENCODE_SERVER_USERNAME)"
    & $add "OPENCODE_SERVER_PASSWORD=$($m.OPENCODE_SERVER_PASSWORD)"
    & $add ''
    & $add '# --- Модель OpenCode ---'
    & $add "OPENCODE_MODEL_PROVIDER=$($m.OPENCODE_MODEL_PROVIDER)"
    & $add "OPENCODE_MODEL_ID=$($m.OPENCODE_MODEL_ID)"
    & $add "# Дешёвая модель для сводок компакции (пусто - модель сессии)"
    & $add "OPENCODE_SMALL_MODEL=$($m.OPENCODE_SMALL_MODEL)"
    & $add '# Какой конфиг монтировать: opencode.jsonc | opencode.local.jsonc'
    & $add "OPENCODE_CONFIG_FILE=$($m.OPENCODE_CONFIG_FILE)"
    & $add ''
    & $add '# --- Ключи провайдеров ---'
    & $add "OPENAI_API_KEY=$($m.OPENAI_API_KEY)"
    & $add "ANTHROPIC_API_KEY=$($m.ANTHROPIC_API_KEY)"
    & $add "OPENROUTER_API_KEY=$($m.OPENROUTER_API_KEY)"
    & $add "CUSTOM_API_KEY=$($m.CUSTOM_API_KEY)"
    & $add ''
    & $add '# --- Локальный провайдер (Ollama / свой endpoint) ---'
    & $add '# Нужны только при OPENCODE_CONFIG_FILE=opencode.local.jsonc.'
    & $add '# Ollama в контейнере - http://ollama:11434/v1, на хосте - host.docker.internal.'
    & $add "OLLAMA_BASE_URL=$($m.OLLAMA_BASE_URL)"
    & $add "CUSTOM_BASE_URL=$($m.CUSTOM_BASE_URL)"
    & $add ''
    & $add '# --- Google Developers API (общий ключ, https://console.cloud.google.com) ---'
    & $add 'GOOGLE_API_KEY='
    & $add '# --- Self-support mode (docs/self-support.md) ---'
    & $add "SELFHOST=$($m.SELFHOST)"
    & $add "HOST_FS_DIR=$($m.HOST_FS_DIR)"
    & $add ''
    & $add '# --- Голос: STT (Whisper-совместимый) ---'
    & $add "STT_API_URL=$($m.STT_API_URL)"
    & $add "STT_API_KEY=$($m.STT_API_KEY)"
    & $add "STT_MODEL=$($m.STT_MODEL)"
    & $add "STT_LANGUAGE=$($m.STT_LANGUAGE)"
    & $add ''
    & $add '# --- Память: Graphiti + FalkorDB ---'
    & $add "# Профиль compose: memory включает память. Пусто - без памяти."
    & $add "COMPOSE_PROFILES=$($m.COMPOSE_PROFILES)"
    & $add "FALKORDB_PASSWORD=$($m.FALKORDB_PASSWORD)"
    & $add "GRAPHITI_IMAGE=$($m.GRAPHITI_IMAGE)"
    & $add "FALKORDB_IMAGE=$($m.FALKORDB_IMAGE)"
    & $add ''
    & $add '# --- Экономия токенов (docs/token-budget.md) ---'
    & $add "GRAPHITI_MODEL=$($m.GRAPHITI_MODEL)"
    & $add "GRAPHITI_SEMAPHORE_LIMIT=$($m.GRAPHITI_SEMAPHORE_LIMIT)"
    & $add "GRAPHITI_DEBOUNCE_MS=$($m.GRAPHITI_DEBOUNCE_MS)"
    & $add "GRAPHITI_MAX_CHARS=$($m.GRAPHITI_MAX_CHARS)"
    & $add "GRAPHITI_SEARCH_TOP_K=$($m.GRAPHITI_SEARCH_TOP_K)"
    & $add ''
    & $add '# --- Docker-образы ---'
    & $add "OPENCODE_IMAGE=$($m.OPENCODE_IMAGE)"
    & $add "BOT_IMAGE=$($m.BOT_IMAGE)"
    & $add ''
    & $add '# --- Прочее ---'
    & $add "TZ=$($m.TZ)"
    & $add "LOG_LEVEL=$($m.LOG_LEVEL)"

    $enc = New-Object System.Text.UTF8Encoding($false)   # без BOM
    [System.IO.File]::WriteAllLines($EnvFile, $l, $enc)
}

# ------------------------------------------------------------------ docker
function Test-Docker {
    if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
        Fail 'Docker не найден.'
        Info 'Установите Docker Desktop: https://www.docker.com/products/docker-desktop/'
        return $false
    }
    docker info *> $null
    if ($LASTEXITCODE -ne 0) {
        Fail 'Docker установлен, но не запущен. Запустите Docker Desktop и повторите.'
        return $false
    }
    docker compose version *> $null
    if ($LASTEXITCODE -ne 0) {
        Fail 'Не найден плагин "docker compose" (Docker Compose v2).'
        return $false
    }
    return $true
}

# ================================================================== main
Write-Host @"

============================================================
          AI-ассистент  -  мастер установки
     OpenCode V2  +  Telegram-бот  +  Graphiti/FalkorDB
============================================================
"@ -ForegroundColor Magenta

Write-Head '1. Проверка Docker'
if (-not (Test-Docker)) { exit 1 }
Ok 'Docker и docker compose готовы'

$d = @{
    TELEGRAM_BOT_TOKEN       = ''
    TELEGRAM_ALLOWED_USER_ID = ''
    BOT_LOCALE               = 'ru'
    OPENCODE_SERVER_VERSION  = 'v2'
    OPENCODE_API_URL         = 'http://opencode:49374'
    OPENCODE_SERVER_USERNAME = 'opencode'
    OPENCODE_SERVER_PASSWORD = ''
    OPENCODE_MODEL_PROVIDER  = 'openai'
    OPENCODE_MODEL_ID        = 'gpt-4o-mini'
    OPENCODE_SMALL_MODEL     = ''
    OPENCODE_CONFIG_FILE     = 'opencode.jsonc'
    OLLAMA_BASE_URL          = 'http://host.docker.internal:11434/v1'
    CUSTOM_BASE_URL          = ''
    OPENAI_API_KEY           = ''
    ANTHROPIC_API_KEY        = ''
    OPENROUTER_API_KEY       = ''
    CUSTOM_API_KEY           = ''
    SELFHOST                 = '0'
    HOST_FS_DIR              = ''
    STT_API_URL              = 'https://api.groq.com/openai/v1'
    STT_API_KEY              = ''
    STT_MODEL                = 'whisper-large-v3-turbo'
    STT_LANGUAGE             = 'ru'
    COMPOSE_PROFILES         = 'memory'
    FALKORDB_PASSWORD        = ''
    GRAPHITI_IMAGE           = 'ghcr.io/your-github-user/ai-assistant-graphiti:latest'
    FALKORDB_IMAGE           = 'falkordb/falkordb:latest'
    GRAPHITI_MODEL           = 'gpt-4o-mini'
    GRAPHITI_SEMAPHORE_LIMIT = '2'
    GRAPHITI_DEBOUNCE_MS     = '180000'
    GRAPHITI_MAX_CHARS       = '12000'
    GRAPHITI_SEARCH_TOP_K    = '5'
    OPENCODE_IMAGE           = 'opencode-v2:local'
    BOT_IMAGE                = 'opencode-telegram-bot:local'
    TZ                       = 'Europe/Moscow'
    LOG_LEVEL                = 'info'
}

if ((Test-Path -LiteralPath $EnvFile) -and -not $Reconfigure) {
    Info 'Найдены прежние настройки в .env — значения подставлены, Enter = оставить.'
    $existing = Read-EnvMap $EnvFile
    foreach ($k in @($d.Keys)) {
        if ($existing.ContainsKey($k) -and $existing[$k] -ne '') { $d[$k] = $existing[$k] }
    }
}

# ---------------------------------------------------------- Telegram
Write-Head '2. Telegram'
$d.TELEGRAM_BOT_TOKEN = AskSecret 'Токен бота (от @BotFather)' $d.TELEGRAM_BOT_TOKEN -Required
if ($d.TELEGRAM_BOT_TOKEN -notmatch '^\d{6,}:[A-Za-z0-9_-]{30,}$') {
    Warn 'Токен не похож на настоящий (формат "123456:ABC..."). Продолжаем, но проверьте.'
}
$d.TELEGRAM_ALLOWED_USER_ID = AskValue 'Ваш числовой Telegram ID (от @userinfobot)' $d.TELEGRAM_ALLOWED_USER_ID -Required
$d.BOT_LOCALE               = AskValue 'Язык интерфейса бота (ru|en|...)' $d.BOT_LOCALE

# ---------------------------------------------------------- LLM
Write-Head '3. Модель OpenCode'
$providers = @(
    @{ key = 'openai';     name = 'OpenAI';                           model = 'gpt-4o-mini';              keyEnv = 'OPENAI_API_KEY' },
    @{ key = 'openrouter'; name = 'OpenRouter';                       model = 'openai/gpt-4o-mini';       keyEnv = 'OPENROUTER_API_KEY' },
    @{ key = 'anthropic';  name = 'Anthropic';                        model = 'claude-3-5-sonnet-latest'; keyEnv = 'ANTHROPIC_API_KEY' },
    @{ key = 'ollama';     name = 'Ollama (локально или на хосте)';   model = 'llama3.1';                 keyEnv = '' },
    @{ key = 'custom';     name = 'Свой OpenAI-совместимый endpoint'; model = $d.OPENCODE_MODEL_ID;       keyEnv = 'CUSTOM_API_KEY' }
)
$chosen = $null
if (-not $Yes) {
    Write-Host 'Выберите провайдера:'
    for ($i = 0; $i -lt $providers.Count; $i++) {
        $mark = if ($providers[$i].key -eq $d.OPENCODE_MODEL_PROVIDER) { '*' } else { ' ' }
        Write-Host ("   {0}) {1} {2}" -f ($i + 1), $mark, $providers[$i].name)
    }
    while ($true) {
        $a = Read-Host 'Номер'
        if ([string]::IsNullOrWhiteSpace($a)) {
            $chosen = ($providers | Where-Object { $_.key -eq $d.OPENCODE_MODEL_PROVIDER } | Select-Object -First 1)
            if (-not $chosen) { $chosen = $providers[0] }
            break
        }
        $n = 0
        if ([int]::TryParse($a, [ref]$n) -and $n -ge 1 -and $n -le $providers.Count) {
            $chosen = $providers[$n - 1]
            # Явный выбор провайдера — модель сбрасывается на его дефолт.
            # Enter выше оставляет провайдера и модель как были.
            $d.OPENCODE_MODEL_ID = $chosen.model
            break
        }
        Warn 'Введите номер из списка.'
    }
} else {
    $chosen = ($providers | Where-Object { $_.key -eq $d.OPENCODE_MODEL_PROVIDER } | Select-Object -First 1)
    if (-not $chosen) { $chosen = $providers[0] }
}
$d.OPENCODE_MODEL_PROVIDER = $chosen.key
$kind = switch ($chosen.key) {
    'openai'     { 'standard' }
    'openrouter' { 'standard' }
    'anthropic'  { 'standard' }
    'ollama'     { 'ollama' }
    default      { 'custom' }
}

if ($kind -eq 'standard') {
    $d.OPENCODE_MODEL_ID    = AskValue 'Модель (без провайдера, напр. gpt-4o-mini)' $d.OPENCODE_MODEL_ID
    $d.OPENCODE_CONFIG_FILE = 'opencode.jsonc'
    if ([string]::IsNullOrWhiteSpace($d.OPENCODE_SMALL_MODEL)) {
        $d.OPENCODE_SMALL_MODEL = switch ($chosen.key) {
            'openai'     { 'openai/gpt-4o-mini' }
            'openrouter' { 'openrouter/openai/gpt-4o-mini' }
            'anthropic'  { 'anthropic/claude-3-5-haiku-latest' }
            default      { '' }
        }
    }
} elseif ($kind -eq 'ollama') {
    $d.OPENCODE_MODEL_ID = AskValue 'Модель Ollama (ollama list, напр. qwen3:8b)' $d.OPENCODE_MODEL_ID
    if ($d.OPENCODE_MODEL_ID -notmatch '^[A-Za-z0-9._:/-]+$') {
        Fail 'В имени модели допустимы буквы, цифры, . _ : / -'; exit 1
    }
    $d.OLLAMA_BASE_URL = AskValue 'Адрес Ollama, видимый из контейнера (с /v1)' $d.OLLAMA_BASE_URL
    $ctx = AskValue 'Контекст модели, токенов (ollama show <модель>)' '8192'
    $d.OPENCODE_CONFIG_FILE = 'opencode.local.jsonc'
    Write-LocalConfig (Get-ProvidersJson 'ollama' $d.OPENCODE_MODEL_ID ([int]$ctx))
} else {
    $d.OPENCODE_MODEL_ID = AskValue 'ID модели у провайдера (как в API)' $d.OPENCODE_MODEL_ID
    if ($d.OPENCODE_MODEL_ID -notmatch '^[A-Za-z0-9._:/-]+$') {
        Fail 'В ID модели допустимы буквы, цифры, . _ : / -'; exit 1
    }
    $d.CUSTOM_BASE_URL = AskValue 'Base URL endpoint (с /v1 в конце)' $d.CUSTOM_BASE_URL -Required
    $ctx = AskValue 'Контекст модели, токенов' '128000'
    $d.OPENCODE_CONFIG_FILE = 'opencode.local.jsonc'
    Write-LocalConfig (Get-ProvidersJson 'custom' $d.OPENCODE_MODEL_ID ([int]$ctx))
}

if ($chosen.keyEnv -ne '') {
    $cur = $d[$chosen.keyEnv]
    $d[$chosen.keyEnv] = AskSecret "API-ключ для $($chosen.name) ($($chosen.keyEnv))" $cur -Required
}

# ---------------------------------------------------------- Whisper / STT
Write-Head '4. Голос (Whisper-совместимый STT)'
# Пресеты STT; текущий определяем по URL, чтобы повторный запуск
# с Enter ничего не менял.
$sttCur = '4'
if ($d.STT_API_URL) {
    if ($d.STT_API_URL -match 'groq\.com') { $sttCur = '1' }
    elseif ($d.STT_API_URL -match 'api\.openai\.com') { $sttCur = '2' }
    else { $sttCur = '3' }
}

$sttPresets = @(
    @{ key = '1'; name = 'Groq — whisper-large-v3-turbo: быстро, есть бесплатный тариф'; url = 'https://api.groq.com/openai/v1'; model = 'whisper-large-v3-turbo' },
    @{ key = '2'; name = 'OpenAI — whisper-1';                                          url = 'https://api.openai.com/v1';        model = 'whisper-1' },
    @{ key = '3'; name = 'Свой OpenAI-совместимый STT';                                 url = '';                                 model = '' },
    @{ key = '4'; name = 'Выключить голос';                                             url = '';                                 model = '' }
)

if (-not $Yes) {
    Write-Host 'Голосовые сообщения (Whisper-совместимый STT):'
    foreach ($p in $sttPresets) {
        $mark = if ($p.key -eq $sttCur) { '*' } else { ' ' }
        Write-Host ("   {0}) {1} {2}" -f $p.key, $mark, $p.name)
    }
    while ($true) {
        $a = Read-Host "Номер [$sttCur]"
        if ([string]::IsNullOrWhiteSpace($a)) { $a = $sttCur }
        $preset = $sttPresets | Where-Object { $_.key -eq $a } | Select-Object -First 1
        if (-not $preset) { Warn 'Введите номер из списка.'; continue }
        if ($a -eq '4') { $d.STT_API_URL = ''; break }
        if ($a -eq '3') {
            $d.STT_API_URL = AskValue 'STT base URL (OpenAI-совместимый, пусто — выключить голос)' $d.STT_API_URL
            if ($d.STT_API_URL) { $d.STT_MODEL = AskValue 'STT модель' $d.STT_MODEL }
            break
        }
        # Ключ прежнего сервиса не подойдёт — забудем, спросим ниже.
        if ($a -ne $sttCur) { $d.STT_API_KEY = '' }
        $d.STT_API_URL = $preset.url
        $d.STT_MODEL   = $preset.model
        break
    }
}

if ($d.STT_API_URL) {
    # Ключ Whisper принадлежит STT-сервису: у OpenAI его можно не дублировать
    # (берём OPENAI_API_KEY), для Groq и своих endpoint'ов он свой.
    $sttDefault = if ($d.STT_API_KEY) { $d.STT_API_KEY }
                  elseif ($d.STT_API_URL -eq 'https://api.openai.com/v1') { $d.OPENAI_API_KEY }
                  else { '' }
    $d.STT_API_KEY  = AskSecret 'STT API-ключ' $sttDefault
    if (-not $d.STT_MODEL) { $d.STT_MODEL = AskValue 'STT модель' 'whisper-1' }
    $d.STT_LANGUAGE = AskValue 'Язык распознавания (пусто — авто)' $d.STT_LANGUAGE
    if (-not $d.STT_API_KEY) {
        Warn 'STT_API_KEY пуст — голосовые не распознаются. Ключ Groq: https://console.groq.com/keys'
    }
}

# ---------------------------------------------------------- Память
Write-Head '5. Память (Graphiti + FalkorDB)'
if ([string]::IsNullOrWhiteSpace($d.FALKORDB_PASSWORD)) {
    $d.FALKORDB_PASSWORD = New-Hex 24
    Ok 'Сгенерирован пароль для FalkorDB.'
}
$d.GRAPHITI_IMAGE = AskValue 'Образ Graphiti MCP' $d.GRAPHITI_IMAGE

# ---------------------------------------------------------- Прочее
Write-Head '6. Прочее'
if ([string]::IsNullOrWhiteSpace($d.OPENCODE_SERVER_PASSWORD)) {
    $d.OPENCODE_SERVER_PASSWORD = New-Hex 24
    Ok 'Сгенерирован пароль для OpenCode Server V2.'
}
$d.SELFHOST  = AskValue 'Режим самоподдержки: агент из контейнера управляет Docker хоста и видит папку хоста в /host (1/0)' $d.SELFHOST
if ($d.SELFHOST -eq '1') {
  $defaultHostFs = $env:USERPROFILE -replace '\\', '/'
  $d.HOST_FS_DIR = AskValue "Папка хоста, видимая агенту в /host (Enter — $defaultHostFs)" $defaultHostFs
}
$d.TZ        = AskValue 'Часовой пояс' $d.TZ
$d.LOG_LEVEL = AskValue 'Уровень логов (debug|info|warn|error)' $d.LOG_LEVEL

Save-Env $d
Ok "Настройки сохранены в $EnvFile"
if ($d.OPENCODE_CONFIG_FILE -eq 'opencode.local.jsonc') {
    Info 'Провайдер локальный: используется opencode\opencode.local.jsonc (пересобирается при запуске мастера).'
}

if ($NoStart) {
    Write-Head 'Готово'
    Info 'Запуск пропущен (-NoStart). Когда будете готовы:  docker compose up -d --build'
    exit 0
}

Write-Head '7. Сборка и запуск контейнеров'
Push-Location $Root
try {
    Info 'docker compose up -d --build (первый запуск собирает образы, это долго) ...'
    docker compose up -d --build
    if ($LASTEXITCODE -ne 0) {
        Fail 'Не удалось запустить. Посмотрите логи:  docker compose logs -f'
        exit 1
    }
} finally {
    Pop-Location
}

Start-Sleep -Seconds 3
docker compose -f (Join-Path $Root 'docker-compose.yml') ps

Write-Host ''
Ok 'Готово!'
Info 'Логи:     docker compose logs -f'
Info 'Стоп:     docker compose down'
Info 'Обновить: docker compose pull && docker compose up -d --build'
