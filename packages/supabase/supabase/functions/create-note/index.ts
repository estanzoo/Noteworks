import { requireAuth } from '../_shared/auth.ts'
import { corsResponse, json, errorResponse } from '../_shared/cors.ts'

const MAX_TITLE = 500

function validate(body: unknown): { title: string; course_id: string } | Response {
  if (body == null || typeof body !== 'object' || Array.isArray(body)) {
    return errorResponse('Validation failed', 'JSON body with title and course_id required', 400)
  }
  const o = body as Record<string, unknown>
  const title = typeof o.title === 'string' ? o.title.trim() : ''
  const courseId = typeof o.course_id === 'string' ? o.course_id.trim() : ''

  const errors: Record<string, string> = {}
  if (!title) errors.title = 'Title is required'
  else if (title.length > MAX_TITLE) errors.title = `Title must be at most ${MAX_TITLE} characters`
  if (!courseId) errors.course_id = 'course_id is required'

  if (Object.keys(errors).length > 0) {
    return errorResponse('Validation failed', 'Invalid input', 400, errors)
  }
  return { title, course_id: courseId }
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return corsResponse()
  if (req.method !== 'POST') {
    return errorResponse('Method not allowed', 'Use POST', 405)
  }

  const auth = await requireAuth(req)
  if (auth instanceof Response) return auth
  const { supabase, user } = auth

  let body: unknown
  try {
    body = await req.json()
  } catch {
    return errorResponse('Bad request', 'Invalid JSON body', 400)
  }

  const validated = validate(body)
  if (validated instanceof Response) return validated

  // Verify course exists
  const { data: course, error: courseErr } = await supabase
    .from('courses')
    .select('id')
    .eq('id', validated.course_id)
    .maybeSingle()

  if (courseErr) {
    return errorResponse('Query failed', courseErr.message, 500)
  }
  if (!course) {
    return errorResponse('Not found', `Course ${validated.course_id} does not exist`, 404)
  }

  const { data: note, error: insertErr } = await supabase
    .from('notes')
    .insert({
      title: validated.title,
      course_id: validated.course_id,
      user_id: user.id,
    })
    .select()
    .single()

  if (insertErr) {
    return errorResponse('Insert failed', insertErr.message, 500)
  }

  return json(note, 201)
})
