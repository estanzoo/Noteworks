import { requireAuth } from '../_shared/auth.ts'
import { corsResponse, json, errorResponse } from '../_shared/cors.ts'

const MAX_PDF_BYTES = 52_428_800 // 50 MB — matches bucket config

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return corsResponse()
  if (req.method !== 'POST') {
    return errorResponse('Method not allowed', 'Use POST', 405)
  }

  const auth = await requireAuth(req)
  if (auth instanceof Response) return auth
  const { supabase, user } = auth

  const url = new URL(req.url)
  const noteId = url.searchParams.get('note_id')
  const filename = url.searchParams.get('filename') ?? 'upload.pdf'

  if (!noteId) {
    return errorResponse('Validation failed', 'Query param note_id is required', 400)
  }

  const contentType = req.headers.get('content-type') ?? ''
  if (!contentType.includes('application/pdf')) {
    return errorResponse('Validation failed', 'Content-Type must be application/pdf', 400)
  }

  // Verify the note exists and belongs to the caller
  const { data: note, error: noteErr } = await supabase
    .from('notes')
    .select('id, user_id')
    .eq('id', noteId)
    .maybeSingle()

  if (noteErr) return errorResponse('Query failed', noteErr.message, 500)
  if (!note) return errorResponse('Not found', 'Note not found or you do not own it', 404)

  // Read PDF binary from request body
  const pdfBytes = await req.arrayBuffer()
  if (pdfBytes.byteLength === 0) {
    return errorResponse('Validation failed', 'Request body is empty — attach a PDF file', 400)
  }
  if (pdfBytes.byteLength > MAX_PDF_BYTES) {
    return errorResponse('Validation failed', `PDF exceeds ${MAX_PDF_BYTES / 1_048_576} MB limit`, 400)
  }

  const storagePath = `${user.id}/${noteId}.pdf`

  // Upload (upsert) to the notes-pdfs bucket
  const { error: uploadErr } = await supabase.storage
    .from('notes-pdfs')
    .upload(storagePath, pdfBytes, {
      contentType: 'application/pdf',
      upsert: true,
    })

  if (uploadErr) {
    return errorResponse('Upload failed', uploadErr.message, 500)
  }

  // Update the note's metadata with PDF info
  const pdfMetadata = {
    pdf_path: storagePath,
    pdf_size_bytes: pdfBytes.byteLength,
    pdf_filename: filename,
    pdf_uploaded_at: new Date().toISOString(),
  }

  const { data: updated, error: updateErr } = await supabase
    .from('notes')
    .update({ metadata: pdfMetadata, updated_at: new Date().toISOString() })
    .eq('id', noteId)
    .select()
    .single()

  if (updateErr) {
    return errorResponse('Metadata update failed', updateErr.message, 500)
  }

  return json(updated, 201)
})
