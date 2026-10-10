#!/usr/bin/env node
// Проверка JSONC (JSON с комментариями) — используется локально и в CI.
// Использование: node scripts/check-jsonc.mjs <файл.jsonc> [ещё файлы...]
import { readFileSync } from 'node:fs';

// Срезает комментарии, не трогая их содержимое внутри строк.
function stripJsonc(src) {
  let out = '';
  let i = 0;
  const n = src.length;
  let inStr = false;
  let inLine = false;
  let inBlock = false;
  let esc = false;
  while (i < n) {
    const c = src[i];
    const next = i + 1 < n ? src[i + 1] : '';
    if (inLine) {
      if (c === '\n') { inLine = false; out += c; }
      i += 1;
      continue;
    }
    if (inBlock) {
      if (c === '*' && next === '/') { inBlock = false; i += 2; continue; }
      if (c === '\n') out += c;
      i += 1;
      continue;
    }
    if (inStr) {
      if (esc) esc = false;
      else if (c === '\\') esc = true;
      else if (c === '"') inStr = false;
      out += c;
      i += 1;
      continue;
    }
    if (c === '"') { inStr = true; out += c; i += 1; continue; }
    if (c === '/' && next === '/') { inLine = true; i += 2; continue; }
    if (c === '/' && next === '*') { inBlock = true; i += 2; continue; }
    out += c;
    i += 1;
  }
  return out;
}

let failed = 0;
for (const file of process.argv.slice(2)) {
  try {
    JSON.parse(stripJsonc(readFileSync(file, 'utf8')));
    console.log(`${file}: valid JSONC`);
  } catch (err) {
    console.error(`${file}: INVALID JSONC — ${err.message}`);
    failed = 1;
  }
}
process.exit(failed);
