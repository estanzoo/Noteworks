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

  // Clean up all PDF versions from storage (current + history)
  const metadata = note.metadata as Record<string, unknown> | null
  const pathsToRemove: string[] = []

  if (metadata?.pdf_path && typeof metadata.pdf_path === 'string') {
    pathsToRemove.push(metadata.pdf_path)
  }
  if (Array.isArray(metadata?.version_history)) {
    for (const p of metadata.version_history as unknown[]) {
      if (typeof p === 'string') pathsToRemove.push(p)
    }
  }

  if (pathsToRemove.length > 0) {
    const { error: storageErr } = await supabase.storage
      .from('notes-pdfs')
      .remove(pathsToRemove)

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
