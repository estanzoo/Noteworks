import { requireAuth } from '../_shared/auth.ts'
import { corsResponse, json, errorResponse } from '../_shared/cors.ts'

const GEMINI_API_KEY = Deno.env.get('GEMINI_API_KEY')
const GEMINI_MODEL = Deno.env.get('GEMINI_MODEL')
const GEMINI_MODEL_FALLBACKS = ['gemini-2.0-flash-lite', 'gemini-2.0-flash', 'gemini-2.5-flash']
const MAX_PDF_BYTES = 16 * 1024 * 1024
const MAX_FILENAME = 160

interface GapDetectInput {
  source_pdf_base64: string
  comparison_pdf_base64: string
  source_filename?: string
  comparison_filename?: string
  source_title?: string
  comparison_title?: string
  course_context?: string
  additional_pdfs_base64?: string[]
  additional_filenames?: string[]
}

interface GapDetectionResponse {
  title: string
  overview: string
  missing_topics: string[]
  extra_topics: string[]
  weak_areas: string[]
  contradictions: string[]
  recommended_additions: string[]
  confidence: 'low' | 'medium' | 'high'
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
    const result = await runGeminiComparison(validated)
    return json(result)
  } catch (error) {
    console.error('gap-detect failed', error)
    const message = error instanceof Error ? error.message : 'Gemini request failed'
    return errorResponse('Gemini failed', message, 502)
  }
})

function validate(raw: unknown): GapDetectInput | Response {
  if (raw == null || typeof raw !== 'object' || Array.isArray(raw)) {
    return errorResponse('Validation failed', 'JSON body required', 400)
  }

  const input = raw as Record<string, unknown>
  const source = asString(input.source_pdf_base64)
  const comparison = asString(input.comparison_pdf_base64)
  if (!source || !comparison) {
    return errorResponse('Validation failed', 'Two base64 PDF fields are required', 400)
  }

  const sourceBytes = estimateBase64Bytes(source)
  const comparisonBytes = estimateBase64Bytes(comparison)
  if (sourceBytes <= 0 || comparisonBytes <= 0) {
    return errorResponse('Validation failed', 'PDF bodies cannot be empty', 400)
  }
  if (sourceBytes > MAX_PDF_BYTES || comparisonBytes > MAX_PDF_BYTES) {
    return errorResponse('Validation failed', `Each PDF must be ${MAX_PDF_BYTES / 1024 / 1024} MB or less`, 400)
  }

  const additional = Array.isArray(input.additional_pdfs_base64)
    ? input.additional_pdfs_base64.filter((item): item is string => typeof item === 'string' && item.trim().length > 0)
    : []
  for (const pdf of additional) {
    const bytes = estimateBase64Bytes(pdf)
    if (bytes <= 0 || bytes > MAX_PDF_BYTES) {
      return errorResponse('Validation failed', `Each additional PDF must be ${MAX_PDF_BYTES / 1024 / 1024} MB or less`, 400)
    }
  }

  return {
    source_pdf_base64: source,
    comparison_pdf_base64: comparison,
    source_filename: trimFilename(input.source_filename, 'source.pdf'),
    comparison_filename: trimFilename(input.comparison_filename, 'comparison.pdf'),
    source_title: asString(input.source_title)?.slice(0, MAX_FILENAME),
    comparison_title: asString(input.comparison_title)?.slice(0, MAX_FILENAME),
    course_context: asString(input.course_context)?.slice(0, 500),
    additional_pdfs_base64: additional.length > 0 ? additional : undefined,
    additional_filenames: stringList(input.additional_filenames),
  }
}

async function runGeminiComparison(input: GapDetectInput): Promise<GapDetectionResponse> {
  const models = unique([GEMINI_MODEL, ...GEMINI_MODEL_FALLBACKS].filter(Boolean) as string[])
  let lastError: Error | null = null

  for (const model of models) {
    try {
      return await runGeminiComparisonWithModel(input, model)
    } catch (error) {
      lastError = error instanceof Error ? error : new Error('Gemini request failed')
    }
  }

  throw lastError ?? new Error('No Gemini model was available')
}

async function runGeminiComparisonWithModel(input: GapDetectInput, model: string): Promise<GapDetectionResponse> {
  const endpoint = `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent?key=${GEMINI_API_KEY}`
  const prompt = buildPrompt(input)

  const parts: Array<Record<string, unknown>> = [
    { text: prompt },
    {
      inline_data: {
        mime_type: 'application/pdf',
        data: input.source_pdf_base64,
      },
    },
    {
      inline_data: {
        mime_type: 'application/pdf',
        data: input.comparison_pdf_base64,
      },
    },
  ]
  for (const pdf of input.additional_pdfs_base64 ?? []) {
    parts.push({
      inline_data: {
        mime_type: 'application/pdf',
        data: pdf,
      },
    })
  }

  const body = {
    contents: [
      {
        role: 'user',
        parts,
      },
    ],
    generationConfig: {
      temperature: 0.25,
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

function buildPrompt(input: GapDetectInput): string {
  return `
You are the Gap Detection engine for Noteworks.

Compare PDF A, the student's current note, against PDF B, the comparison note or class material.
Any additional PDFs are optional class materials that provide extra context.

PDF A filename: ${input.source_filename}
PDF A title: ${input.source_title ?? 'Current note'}
PDF B filename: ${input.comparison_filename}
PDF B title: ${input.comparison_title ?? 'Comparison PDF'}
Course context: ${input.course_context ?? 'Unknown'}
Additional class materials: ${(input.additional_filenames ?? []).join(', ') || 'None'}

Return ONLY valid JSON with these snake_case keys:
{
  "title": "Gap Detection Summary",
  "overview": "2-4 sentence student-friendly summary of the most important differences.",
  "missing_topics": ["topics or ideas that PDF B covers but PDF A misses"],
  "extra_topics": ["topics PDF A covers that PDF B does not emphasize"],
  "weak_areas": ["areas in PDF A that are present but too shallow, unclear, or unsupported"],
  "contradictions": ["possible conflicts or mismatches between the PDFs"],
  "recommended_additions": ["specific additions the student should add to PDF A"],
  "confidence": "low | medium | high"
}

Keep every list to at most 6 concise items. Prefer concrete course concepts over generic study advice.
`.trim()
}

function normalizeGeminiJSON(raw: Record<string, unknown>): GapDetectionResponse {
  return {
    title: asString(raw.title) || 'Gap Detection Summary',
    overview: asString(raw.overview) || 'Gemini compared the two PDFs and found the differences below.',
    missing_topics: stringList(raw.missing_topics),
    extra_topics: stringList(raw.extra_topics),
    weak_areas: stringList(raw.weak_areas),
    contradictions: stringList(raw.contradictions),
    recommended_additions: stringList(raw.recommended_additions),
    confidence: normalizeConfidence(raw.confidence),
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
    .slice(0, 6)
}

function normalizeConfidence(value: unknown): 'low' | 'medium' | 'high' {
  if (value === 'low' || value === 'medium' || value === 'high') return value
  return 'medium'
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
