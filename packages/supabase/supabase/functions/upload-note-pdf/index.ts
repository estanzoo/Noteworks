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

  // ── Parse params ──────────────────────────────────────────────
  const url = new URL(req.url)
  const noteId = url.searchParams.get('note_id')
  const filename = url.searchParams.get('filename') ?? 'upload.pdf'
  const courseId = url.searchParams.get('course_id')
  const title = url.searchParams.get('title') ?? filename.replace(/\.pdf$/i, '')

  if (!noteId) {
    return errorResponse('Validation failed', 'Query param note_id is required', 400)
  }

  const contentType = req.headers.get('content-type') ?? ''
  if (!contentType.includes('application/pdf')) {
    return errorResponse('Validation failed', 'Content-Type must be application/pdf', 400)
  }

  // ── Read and validate PDF body ────────────────────────────────
  const pdfBytes = await req.arrayBuffer()
  if (pdfBytes.byteLength === 0) {
    return errorResponse('Validation failed', 'Request body is empty — attach a PDF file', 400)
  }
  if (pdfBytes.byteLength > MAX_PDF_BYTES) {
    return errorResponse('Validation failed', `PDF exceeds ${MAX_PDF_BYTES / 1_048_576} MB limit`, 400)
  }

  // ── Check if note already exists ──────────────────────────────
  const { data: existingNote, error: lookupErr } = await supabase
    .from('notes')
    .select('id, user_id, metadata')
    .eq('id', noteId)
    .maybeSingle()

  if (lookupErr) {
    return errorResponse('Query failed', lookupErr.message, 500)
  }

  const now = new Date().toISOString()
  const isNew = !existingNote

  if (isNew) {
    return await handleNewNote({
      supabase, user, noteId, courseId, title, filename, pdfBytes, now,
    })
  }

  return await handleExistingNote({
    supabase, user, existingNote, filename, pdfBytes, now,
  })
})

// ── New note: create row + first upload ─────────────────────────

interface NewNoteArgs {
  supabase: ReturnType<typeof import('https://esm.sh/@supabase/supabase-js@2').createClient>
  user: { id: string }
  noteId: string
  courseId: string | null
  title: string
  filename: string
  pdfBytes: ArrayBuffer
  now: string
}

async function handleNewNote({
  supabase, user, noteId, courseId, title, filename, pdfBytes, now,
}: NewNoteArgs) {
  if (!courseId) {
    return errorResponse(
      'Validation failed',
      'course_id is required when uploading to a new note',
      400,
    )
  }

  // Verify course exists
  const { data: course, error: courseErr } = await supabase
    .from('courses')
    .select('id')
    .eq('id', courseId)
    .maybeSingle()

  if (courseErr) return errorResponse('Query failed', courseErr.message, 500)
  if (!course) {
    return errorResponse('Not found', `Course ${courseId} does not exist`, 404)
  }

  const storagePath = `${user.id}/${noteId}/v_1.pdf`

  const { error: uploadErr } = await supabase.storage
    .from('notes-pdfs')
    .upload(storagePath, pdfBytes, { contentType: 'application/pdf' })

  if (uploadErr) return errorResponse('Upload failed', uploadErr.message, 500)

  const metadata = {
    pdf_path: storagePath,
    pdf_size_bytes: pdfBytes.byteLength,
    pdf_filename: filename,
    pdf_uploaded_at: now,
    version: 1,
    version_history: [] as string[],
  }

  const { error: insertErr } = await supabase
    .from('notes')
    .insert({
      id: noteId,
      title,
      course_id: courseId,
      user_id: user.id,
      metadata,
    })

  if (insertErr) {
    // Roll back the uploaded file
    await supabase.storage.from('notes-pdfs').remove([storagePath])
    return errorResponse('Insert failed', insertErr.message, 500)
  }

  return json({ success: true }, 201)
}

// ── Existing note: archive old version + upload new ─────────────

interface ExistingNoteArgs {
  supabase: ReturnType<typeof import('https://esm.sh/@supabase/supabase-js@2').createClient>
  user: { id: string }
  existingNote: { id: string; user_id: string; metadata: unknown }
  filename: string
  pdfBytes: ArrayBuffer
  now: string
}

async function handleExistingNote({
  supabase, user, existingNote, filename, pdfBytes, now,
}: ExistingNoteArgs) {
  const meta = existingNote.metadata as Record<string, unknown> | null
  const currentVersion = (meta?.version as number) ?? 0
  const prevHistory = (meta?.version_history as string[]) ?? []

  // Push the current pdf_path into history before we overwrite it
  if (meta?.pdf_path && typeof meta.pdf_path === 'string') {
    prevHistory.push(meta.pdf_path)
  }

  const nextVersion = currentVersion + 1
  const storagePath = `${user.id}/${existingNote.id}/v_${nextVersion}.pdf`

  const { error: uploadErr } = await supabase.storage
    .from('notes-pdfs')
    .upload(storagePath, pdfBytes, { contentType: 'application/pdf' })

  if (uploadErr) return errorResponse('Upload failed', uploadErr.message, 500)

  const updatedMetadata = {
    pdf_path: storagePath,
    pdf_size_bytes: pdfBytes.byteLength,
    pdf_filename: filename,
    pdf_uploaded_at: now,
    version: nextVersion,
    version_history: prevHistory,
  }

  const { error: updateErr } = await supabase
    .from('notes')
    .update({ metadata: updatedMetadata, updated_at: now })
    .eq('id', existingNote.id)

  if (updateErr) {
    return errorResponse('Metadata update failed', updateErr.message, 500)
  }

  return json({ success: true })
}
