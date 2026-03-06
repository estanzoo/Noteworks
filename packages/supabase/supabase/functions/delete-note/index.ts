import { requireAuth } from '../_shared/auth.ts'
import { corsResponse, json, errorResponse } from '../_shared/cors.ts'

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return corsResponse()
  if (req.method !== 'DELETE') {
    return errorResponse('Method not allowed', 'Use DELETE', 405)
  }

  const auth = await requireAuth(req)
  if (auth instanceof Response) return auth
  const { supabase, user } = auth

  const url = new URL(req.url)
  const noteId = url.searchParams.get('id')

  if (!noteId) {
    return errorResponse('Validation failed', 'Query param id is required', 400)
  }

  // Fetch note to check ownership and get PDF path
  const { data: note, error: fetchErr } = await supabase
    .from('notes')
    .select('id, user_id, metadata')
    .eq('id', noteId)
    .maybeSingle()

  if (fetchErr) return errorResponse('Query failed', fetchErr.message, 500)
  if (!note) return errorResponse('Not found', 'Note not found or you do not own it', 404)

  // Clean up associated PDF from storage if it exists
  const metadata = note.metadata as Record<string, unknown> | null
  if (metadata?.pdf_path && typeof metadata.pdf_path === 'string') {
    const { error: storageErr } = await supabase.storage
      .from('notes-pdfs')
      .remove([metadata.pdf_path])

    if (storageErr) {
      console.error('PDF cleanup failed (non-blocking):', storageErr.message)
    }
  }

  const { error: deleteErr } = await supabase
    .from('notes')
    .delete()
    .eq('id', noteId)

  if (deleteErr) {
    return errorResponse('Delete failed', deleteErr.message, 500)
  }

  return json({ message: 'Note deleted', id: noteId })
})
