import { readFileSync, writeFileSync } from 'fs'
import { resolve, dirname } from 'path'
import { fileURLToPath } from 'url'

const __dirname = dirname(fileURLToPath(import.meta.url))
const ROOT = resolve(__dirname, '..')

const sql = readFileSync(
  resolve(ROOT, 'packages/supabase/supabase/migrations/20260410100001_seed_schools.sql'),
  'utf-8'
)

const lines = sql.split('\n').filter((l) => l.trim().startsWith('('))

const ROW_RE =
  /\('((?:[^']|'')*)',\s*'((?:[^']|'')*)',\s*'((?:[^']|'')*)',\s*'((?:[^']|'')*)',\s*'((?:[^']|'')*)'\)/

function unescapeSQL(s: string): string {
  return s.replace(/''/g, "'")
}

function csvEscape(s: string): string {
  if (s.includes(',') || s.includes('"') || s.includes('\n')) {
    return '"' + s.replace(/"/g, '""') + '"'
  }
  return s
}

const rows: string[] = []
for (const line of lines) {
  const m = line.match(ROW_RE)
  if (!m) continue
  const fields = [m[1], m[2], m[3], m[4], m[5]].map(unescapeSQL).map(csvEscape)
  rows.push(fields.join(','))
}

const csv = 'name,location,country,state_province,city\n' + rows.join('\n') + '\n'
const outPath = resolve(ROOT, 'data/schools.csv')
writeFileSync(outPath, csv, 'utf-8')
console.log(`Wrote ${rows.length} rows to ${outPath}`)
