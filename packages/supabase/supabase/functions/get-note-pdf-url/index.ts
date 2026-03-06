import { requireAuth } from '../_shared/auth.ts'
import { corsResponse, json, errorResponse } from '../_shared/cors.ts'

const DEFAULT_EXPIRY_SECONDS = 3600 // 1 hour

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return corsResponse()
  if (req.method !== 'GET') {
    return errorResponse('Method not allowed', 'Use GET', 405)
  }

  const auth = await requireAuth(req)
  if (auth instanceof Response) return auth
  const { supabase } = auth

  const url = new URL(req.url)
  const noteId = url.searchParams.get('note_id')
  const expiresIn = Math.min(
    86400,
    Math.max(60, Number(url.searchParams.get('expires_in') ?? DEFAULT_EXPIRY_SECONDS)),
  )

  if (!noteId) {
    return errorResponse('Validation failed', 'Query param note_id is required', 400)
  }

  // Fetch note (RLS enforces ownership / enrollment visibility)
  const { data: note, error: noteErr } = await supabase
    .from('notes')
    .select('id, metadata')
    .eq('id', noteId)
    .maybeSingle()

  if (noteErr) return errorResponse('Query failed', noteErr.message, 500)
  if (!note) return errorResponse('Not found', 'Note not found', 404)

  const metadata = note.metadata as Record<string, unknown> | null
  if (!metadata?.pdf_path || typeof metadata.pdf_path !== 'string') {
    return errorResponse('Not found', 'This note has no PDF attached', 404)
  }

  const { data: signed, error: signErr } = await supabase.storage
    .from('notes-pdfs')
    .createSignedUrl(metadata.pdf_path, expiresIn)

  if (signErr || !signed?.signedUrl) {
    return errorResponse('Storage error', signErr?.message ?? 'Could not generate signed URL', 500)
  }

  return json({
    note_id: noteId,
    pdf_filename: metadata.pdf_filename ?? null,
    signed_url: signed.signedUrl,
    expires_in: expiresIn,
  })
})
