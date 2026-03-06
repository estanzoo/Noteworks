import { requireAuth } from '../_shared/auth.ts'
import { corsResponse, json, errorResponse } from '../_shared/cors.ts'

const MAX_TITLE = 500

function validate(body: unknown): { note_id: string; title?: string; metadata?: Record<string, unknown> } | Response {
  if (body == null || typeof body !== 'object' || Array.isArray(body)) {
    return errorResponse('Validation failed', 'JSON body with note_id required', 400)
  }
  const o = body as Record<string, unknown>
  const noteId = typeof o.note_id === 'string' ? o.note_id.trim() : ''

  if (!noteId) {
    return errorResponse('Validation failed', 'note_id is required', 400)
  }

  const updates: { note_id: string; title?: string; metadata?: Record<string, unknown> } = { note_id: noteId }

  if (o.title !== undefined) {
    const title = typeof o.title === 'string' ? o.title.trim() : ''
    if (!title) return errorResponse('Validation failed', 'Title cannot be empty', 400)
    if (title.length > MAX_TITLE) return errorResponse('Validation failed', `Title must be at most ${MAX_TITLE} characters`, 400)
    updates.title = title
  }

  if (o.metadata !== undefined) {
    if (o.metadata !== null && (typeof o.metadata !== 'object' || Array.isArray(o.metadata))) {
      return errorResponse('Validation failed', 'metadata must be a JSON object or null', 400)
    }
    updates.metadata = o.metadata as Record<string, unknown>
  }

  if (!updates.title && updates.metadata === undefined) {
    return errorResponse('Validation failed', 'Provide at least title or metadata to update', 400)
  }

  return updates
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return corsResponse()
  if (req.method !== 'PATCH') {
    return errorResponse('Method not allowed', 'Use PATCH', 405)
  }

  const auth = await requireAuth(req)
  if (auth instanceof Response) return auth
  const { supabase } = auth

  let body: unknown
  try {
    body = await req.json()
  } catch {
    return errorResponse('Bad request', 'Invalid JSON body', 400)
  }

  const validated = validate(body)
  if (validated instanceof Response) return validated

  const { note_id, ...fields } = validated

  const updatePayload: Record<string, unknown> = { ...fields, updated_at: new Date().toISOString() }

  const { data, error } = await supabase
    .from('notes')
    .update(updatePayload)
    .eq('id', note_id)
    .select()
    .single()

  if (error) {
    if (error.code === 'PGRST116') {
      return errorResponse('Not found', 'Note not found or you do not own it', 404)
    }
    return errorResponse('Update failed', error.message, 500)
  }

  return json(data)
})
