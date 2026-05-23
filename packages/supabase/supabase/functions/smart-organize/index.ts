import { requireAuth } from '../_shared/auth.ts'
import { corsResponse, json, errorResponse } from '../_shared/cors.ts'

const GEMINI_API_KEY = Deno.env.get('GEMINI_API_KEY')
const GEMINI_MODEL = Deno.env.get('GEMINI_MODEL')
const GEMINI_MODEL_FALLBACKS = ['gemini-2.0-flash-lite', 'gemini-2.0-flash', 'gemini-2.5-flash']
const MAX_PDF_BYTES = 16 * 1024 * 1024
const MAX_FILENAME = 160

interface SmartOrganizeInput {
  note_pdf_base64: string
  filename?: string
  note_title?: string
  page_count?: number
  course_context?: string
}

interface SmartOrganizationSection {
  heading: string
  bullets: string[]
}

interface SmartOrganizationResponse {
  sections: SmartOrganizationSection[]
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return corsResponse()
  if (req.method !== 'POST') {
    return errorResponse('Method not allowed', 'Use POST', 405)
  }

  if (!GEMINI_API_KEY) {
    return errorResponse('Server not configured', 'Missing GEMINI_API_KEY secret', 500)
  }

  const auth = await requireAuth(req)
  if (auth instanceof Response) return auth

  let raw: unknown
  try {
    raw = await req.json()
  } catch {
    return errorResponse('Bad request', 'Invalid JSON body', 400)
  }

  const validated = validate(raw)
  if (validated instanceof Response) return validated

  try {
    const result = await runGeminiOrganize(validated)
    return json(result)
  } catch (error) {
    console.error('smart-organize failed', error)
    const message = error instanceof Error ? error.message : 'Gemini request failed'
    return errorResponse('Gemini failed', message, 502)
  }
})

function validate(raw: unknown): SmartOrganizeInput | Response {
  if (raw == null || typeof raw !== 'object' || Array.isArray(raw)) {
    return errorResponse('Validation failed', 'JSON body required', 400)
  }

  const input = raw as Record<string, unknown>
  const pdf = asString(input.note_pdf_base64)
  if (!pdf) {
    return errorResponse('Validation failed', 'note_pdf_base64 is required', 400)
  }

  const bytes = estimateBase64Bytes(pdf)
  if (bytes <= 0) {
    return errorResponse('Validation failed', 'PDF body cannot be empty', 400)
  }
  if (bytes > MAX_PDF_BYTES) {
    return errorResponse('Validation failed', `PDF must be ${MAX_PDF_BYTES / 1024 / 1024} MB or less`, 400)
  }

  const pageCount = typeof input.page_count === 'number' && input.page_count > 0
    ? Math.floor(input.page_count)
    : 1

  return {
    note_pdf_base64: pdf,
    filename: trimFilename(input.filename, 'note.pdf'),
    note_title: asString(input.note_title)?.slice(0, MAX_FILENAME),
    page_count: pageCount,
    course_context: asString(input.course_context)?.slice(0, 500),
  }
}

async function runGeminiOrganize(input: SmartOrganizeInput): Promise<SmartOrganizationResponse> {
  const models = unique([GEMINI_MODEL, ...GEMINI_MODEL_FALLBACKS].filter(Boolean) as string[])
  let lastError: Error | null = null

  for (const model of models) {
    try {
      return await runGeminiOrganizeWithModel(input, model)
    } catch (error) {
      lastError = error instanceof Error ? error : new Error('Gemini request failed')
    }
  }

  throw lastError ?? new Error('No Gemini model was available')
}

async function runGeminiOrganizeWithModel(input: SmartOrganizeInput, model: string): Promise<SmartOrganizationResponse> {
  const endpoint = `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent?key=${GEMINI_API_KEY}`
  const prompt = buildPrompt(input)

  const body = {
    contents: [
      {
        role: 'user',
        parts: [
          { text: prompt },
          {
            inline_data: {
              mime_type: 'application/pdf',
              data: input.note_pdf_base64,
            },
          },
        ],
      },
    ],
    generationConfig: {
      temperature: 0.3,
      response_mime_type: 'application/json',
    },
  }

  const response = await fetch(endpoint, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
  })

  const text = await response.text()
  if (!response.ok) {
    throw new Error(`Gemini returned ${response.status}: ${text.slice(0, 500)}`)
  }

  const parsed = JSON.parse(text)
  const modelText = parsed?.candidates?.[0]?.content?.parts
    ?.map((part: { text?: string }) => part.text ?? '')
    .join('')
    .trim()

  if (!modelText) throw new Error('Gemini returned an empty response')

  return normalizeGeminiJSON(JSON.parse(stripCodeFence(modelText)))
}

function buildPrompt(input: SmartOrganizeInput): string {
  return `
You are the Smart Organization engine for Noteworks.

Analyze the student's note PDF and describe how you would reorganize it for clarity.
Do not rewrite the note — return a concise summary of proposed structural changes.

Note title: ${input.note_title ?? 'Current note'}
Page count: ${input.page_count ?? 1}
Course context: ${input.course_context ?? 'Unknown'}

Return ONLY valid JSON:
{
  "sections": [
    {
      "heading": "STRUCTURE",
      "bullets": ["3-5 bullets about section order, merged blocks, renamed headings"]
    },
    {
      "heading": "READABILITY",
      "bullets": ["3-5 bullets about paragraph tightening, bullets, duplicates removed"]
    },
    {
      "heading": "NEXT STEPS",
      "bullets": ["3-5 bullets the student should review after reorganization"]
    }
  ]
}

Each bullet should start with "- ". Keep bullets concrete and tied to the note content when possible.
`.trim()
}

function normalizeGeminiJSON(raw: Record<string, unknown>): SmartOrganizationResponse {
  const sections = Array.isArray(raw.sections) ? raw.sections : []
  return {
    sections: sections
      .map((item) => normalizeSection(item))
      .filter((section): section is SmartOrganizationSection => section != null)
      .slice(0, 6),
  }
}

function normalizeSection(value: unknown): SmartOrganizationSection | null {
  if (value == null || typeof value !== 'object' || Array.isArray(value)) return null
  const item = value as Record<string, unknown>
  const heading = asString(item.heading)
  if (!heading) return null
  return {
    heading,
    bullets: stringList(item.bullets).slice(0, 6),
  }
}

function asString(value: unknown): string | undefined {
  return typeof value === 'string' ? value.trim() : undefined
}

function stringList(value: unknown): string[] {
  if (!Array.isArray(value)) return []
  return value
    .filter((item): item is string => typeof item === 'string')
    .map((item) => item.trim())
    .filter(Boolean)
}

function trimFilename(value: unknown, fallback: string): string {
  const text = asString(value) || fallback
  return text.slice(0, MAX_FILENAME)
}

function estimateBase64Bytes(value: string): number {
  const padding = value.endsWith('==') ? 2 : value.endsWith('=') ? 1 : 0
  return Math.floor(value.length * 0.75) - padding
}

function stripCodeFence(value: string): string {
  return value
    .replace(/^```(?:json)?/i, '')
    .replace(/```$/i, '')
    .trim()
}

function unique(values: string[]): string[] {
  return Array.from(new Set(values))
}
