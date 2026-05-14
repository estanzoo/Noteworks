import { requireAuth } from '../_shared/auth.ts'
import { corsResponse, json, errorResponse } from '../_shared/cors.ts'

const MAX_PDF_BYTES = 52_428_800 // 50 MB — matches bucket config
const BUCKET = 'notes-pdfs'
const DEFAULT_SIGNED_URL_TTL = 3600 // 1 hour

// Direct PDF upload to Storage — does NOT touch the `notes` table.
// Useful for raw uploads (drafts, scratch files, pre-creation flows, etc.).
//
// Request:
//   POST /functions/v1/upload-pdf
//   Headers:
//     Authorization: Bearer <jwt>
//     Content-Type: application/pdf
//   Query params (all optional):
//     path        — relative path under the caller's user folder
//                   (e.g. "drafts/foo.pdf"). If omitted, a UUID-based
//                   filename is generated.
//     filename    — original filename; recorded in response only.
//     upsert      — "true" to overwrite an existing object at the same path.
//     signed_url  — "true" (default) to also return a short-lived signed URL.
//     expires_in  — TTL in seconds for the signed URL (60..86400).
//
// Response 201:
//   {
//     success: true,
//     bucket: "notes-pdfs",
//     path: "<user_id>/<...>.pdf",
//     size_bytes: number,
//     filename: string | null,
//     signed_url?: string,
//     expires_in?: number
//   }
Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return corsResponse()
  if (req.method !== 'POST') {
    return errorResponse('Method not allowed', 'Use POST', 405)
  }

  const auth = await requireAuth(req)
  if (auth instanceof Response) return auth
  const { supabase, user } = auth

  const contentType = req.headers.get('content-type') ?? ''
  if (!contentType.includes('application/pdf')) {
    return errorResponse('Validation failed', 'Content-Type must be application/pdf', 400)
  }

  const url = new URL(req.url)
  const rawPath = url.searchParams.get('path')?.trim() ?? ''
  const filename = url.searchParams.get('filename')?.trim() || null
  const upsert = url.searchParams.get('upsert') === 'true'
  const wantSignedUrl = (url.searchParams.get('signed_url') ?? 'true') !== 'false'
  const expiresIn = Math.min(
    86400,
    Math.max(60, Number(url.searchParams.get('expires_in') ?? DEFAULT_SIGNED_URL_TTL)),
  )

  const storagePath = resolveStoragePath(user.id, rawPath)
  if (storagePath instanceof Response) return storagePath

  const pdfBytes = await req.arrayBuffer()
  if (pdfBytes.byteLength === 0) {
    return errorResponse('Validation failed', 'Request body is empty — attach a PDF file', 400)
  }
  if (pdfBytes.byteLength > MAX_PDF_BYTES) {
    return errorResponse(
      'Validation failed',
      `PDF exceeds ${MAX_PDF_BYTES / 1_048_576} MB limit`,
      400,
    )
  }

  const { error: uploadErr } = await supabase.storage
    .from(BUCKET)
    .upload(storagePath, pdfBytes, {
      contentType: 'application/pdf',
      upsert,
    })

  if (uploadErr) {
    const msg = uploadErr.message ?? 'Upload failed'
    const isConflict = /exists|duplicate/i.test(msg)
    return errorResponse(
      'Upload failed',
      msg,
      isConflict ? 409 : 500,
    )
  }

  const body: Record<string, unknown> = {
    success: true,
    bucket: BUCKET,
    path: storagePath,
    size_bytes: pdfBytes.byteLength,
    filename,
  }

  if (wantSignedUrl) {
    const { data: signed, error: signErr } = await supabase.storage
      .from(BUCKET)
      .createSignedUrl(storagePath, expiresIn)

    if (signErr || !signed?.signedUrl) {
      // The upload itself succeeded — surface the failure but don't roll back.
      body.signed_url = null
      body.signed_url_error = signErr?.message ?? 'Could not generate signed URL'
    } else {
      body.signed_url = signed.signedUrl
      body.expires_in = expiresIn
    }
  }

  return json(body, 201)
})

// Builds a safe storage path under the caller's user folder.
// Storage RLS requires (storage.foldername(name))[1] = auth.uid().
function resolveStoragePath(userId: string, rawPath: string): string | Response {
  if (!rawPath) {
    return `${userId}/${crypto.randomUUID()}.pdf`
  }

  // Strip leading slashes and a redundant "<user_id>/" prefix if the
  // caller already included it.
  let cleaned = rawPath.replace(/^\/+/, '')
  const prefix = `${userId}/`
  if (cleaned.startsWith(prefix)) {
    cleaned = cleaned.slice(prefix.length)
  }

  if (!cleaned) {
    return errorResponse('Validation failed', 'path is empty after normalization', 400)
  }
  if (cleaned.includes('..')) {
    return errorResponse('Validation failed', 'path must not contain ".."', 400)
  }
  if (cleaned.length > 512) {
    return errorResponse('Validation failed', 'path is too long (max 512 chars)', 400)
  }
  if (!/\.pdf$/i.test(cleaned)) {
    cleaned = `${cleaned}.pdf`
  }

  return `${userId}/${cleaned}`
}
