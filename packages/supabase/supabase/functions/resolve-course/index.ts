import { requireAuth } from '../_shared/auth.ts'
import { corsResponse, json, errorResponse } from '../_shared/cors.ts'

const MAX_CODE = 50
const MAX_NAME = 255

interface ValidInput {
  code: string
  name: string
  school_id: string | null
}

function normalizeCode(value: string): string {
  return value.trim().replace(/\s+/g, '').toUpperCase().slice(0, MAX_CODE)
}

function validate(raw: unknown): ValidInput | Response {
  if (raw == null || typeof raw !== 'object' || Array.isArray(raw)) {
    return errorResponse('Validation failed', 'JSON body required', 400)
  }
  const o = raw as Record<string, unknown>
  const codeSource = typeof o.code === 'string' ? o.code : ''
  const code = normalizeCode(codeSource)
  const nameSource = typeof o.name === 'string' ? o.name.trim() : code
  const name = (nameSource || code).slice(0, MAX_NAME)
  const schoolId = typeof o.school_id === 'string' && /^[0-9a-f-]{36}$/i.test(o.school_id)
    ? o.school_id
    : null

  const errors: Record<string, string> = {}
  if (!code) errors.code = 'Course code is required'
  if (code.length > MAX_CODE) errors.code = `Course code must be at most ${MAX_CODE} characters`
  if (!name) errors.name = 'Course name is required'

  if (Object.keys(errors).length > 0) {
    return errorResponse('Validation failed', 'Invalid input', 400, errors)
  }
  return { code, name, school_id: schoolId }
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return corsResponse()
  if (req.method !== 'POST') {
    return errorResponse('Method not allowed', 'Use POST', 405)
  }

  const auth = await requireAuth(req)
  if (auth instanceof Response) return auth
  const { supabase, user } = auth

  let raw: unknown
  try {
    raw = await req.json()
  } catch {
    return errorResponse('Bad request', 'Invalid JSON body', 400)
  }

  const validated = validate(raw)
  if (validated instanceof Response) return validated

  let course: { id: string; code: string | null; name: string | null } | null = null

  const { data: existing, error: lookupErr } = await supabase
    .from('courses')
    .select('id, code, name')
    .eq('code', validated.code)
    .maybeSingle()

  if (lookupErr) return errorResponse('Query failed', lookupErr.message, 500)
  course = existing

  if (!course) {
    const { data: inserted, error: insertErr } = await supabase
      .from('courses')
      .insert({
        code: validated.code,
        name: validated.name,
      })
      .select('id, code, name')
      .single()

    if (insertErr) return errorResponse('Insert failed', insertErr.message, 500)
    course = inserted
  }
  if (!course) {
    return errorResponse('Insert failed', 'Course could not be resolved', 500)
  }

  if (validated.school_id) {
    const { error: schoolLinkErr } = await supabase
      .from('school_courses')
      .upsert(
        { school_id: validated.school_id, course_id: course.id },
        { onConflict: 'school_id,course_id', ignoreDuplicates: true },
      )
    if (schoolLinkErr) {
      console.error('school_courses upsert failed:', schoolLinkErr.message)
    }
  }

  const { error: enrollmentErr } = await supabase
    .from('course_enrollments')
    .upsert(
      { course_id: course.id, user_id: user.id, enrolled_at: new Date().toISOString() },
      { onConflict: 'course_id,user_id', ignoreDuplicates: true },
    )
  if (enrollmentErr) {
    console.error('course_enrollments upsert failed:', enrollmentErr.message)
  }

  return json({
    id: course.id,
    code: course.code ?? validated.code,
    name: course.name ?? validated.name,
  })
})
