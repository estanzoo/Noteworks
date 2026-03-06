// Submit onboarding: school, year of study, course codes; update users and create enrollments
import { requireAuth } from '../_shared/auth.ts'
import { corsResponse, json, errorResponse } from '../_shared/cors.ts'

const MAX_NAME = 255
const MAX_YEAR = 100
const MAX_SCHOOL = 255
const MAX_EMAIL = 255
const MAX_COURSE_CODE = 50
const MAX_COURSE_CODES = 50

const EMAIL_REGEX = /^[^\s@]+@[^\s@]+\.[^\s@]+$/

type ValidBody = {
  name: string
  year_of_study: string
  school_affiliation: string
  school_email: string
  course_codes: string[]
}

function validate(body: unknown): ValidBody | { errors: Record<string, string> } {
  if (body == null || typeof body !== 'object' || Array.isArray(body)) {
    return {
      errors: {
        body:
          'JSON body with name, year_of_study, school_affiliation, school_email, course_codes required',
      },
    }
  }
  const o = body as Record<string, unknown>
  const name = typeof o.name === 'string' ? o.name.trim() : ''
  const year_of_study = typeof o.year_of_study === 'string' ? o.year_of_study.trim() : ''
  const school_affiliation =
    typeof o.school_affiliation === 'string' ? o.school_affiliation.trim() : ''
  const school_email = typeof o.school_email === 'string' ? o.school_email.trim() : ''

  let course_codes: string[] = []
  if (Array.isArray(o.course_codes)) {
    course_codes = o.course_codes
      .filter((c): c is string => typeof c === 'string')
      .map((c) => c.trim())
      .filter((c) => c.length > 0)
  }

  const errors: Record<string, string> = {}

  if (name.length === 0) errors.name = 'Name is required'
  else if (name.length > MAX_NAME) errors.name = `Name must be at most ${MAX_NAME} characters`

  if (year_of_study.length === 0) errors.year_of_study = 'Year of study is required'
  else if (year_of_study.length > MAX_YEAR)
    errors.year_of_study = `Year of study must be at most ${MAX_YEAR} characters`

  if (school_affiliation.length === 0) errors.school_affiliation = 'School is required'
  else if (school_affiliation.length > MAX_SCHOOL)
    errors.school_affiliation = `School must be at most ${MAX_SCHOOL} characters`

  if (school_email.length === 0) errors.school_email = 'School email is required'
  else if (!EMAIL_REGEX.test(school_email)) errors.school_email = 'Invalid email format'
  else if (school_email.length > MAX_EMAIL)
    errors.school_email = `School email must be at most ${MAX_EMAIL} characters`

  if (course_codes.length > MAX_COURSE_CODES)
    errors.course_codes = `At most ${MAX_COURSE_CODES} course codes allowed`
  for (let i = 0; i < course_codes.length; i++) {
    if (course_codes[i].length > MAX_COURSE_CODE) {
      errors[`course_codes[${i}]`] = `Course code must be at most ${MAX_COURSE_CODE} characters`
      break
    }
  }

  if (Object.keys(errors).length > 0) return { errors }
  return { name, year_of_study, school_affiliation, school_email, course_codes }
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
  if ('errors' in validated) {
    return json({ error: 'Validation failed', errors: validated.errors }, 400)
  }

  const now = new Date().toISOString()

  const { data: updated, error: updateError } = await supabase
    .from('users')
    .update({
      name: validated.name,
      year_of_study: validated.year_of_study,
      school_affiliation: validated.school_affiliation,
      school_email: validated.school_email,
      course_codes: validated.course_codes,
      onboarding_completed_at: now,
      updated_at: now,
    })
    .eq('id', user.id)
    .select()
    .single()

  if (updateError) {
    if (updateError.code === 'PGRST116') {
      return errorResponse('Not found', 'User profile not found', 404)
    }
    return errorResponse('Update failed', updateError.message, 500)
  }

  // Resolve school by name and create school enrollment if found
  const { data: schoolRow } = await supabase
    .from('schools')
    .select('id')
    .ilike('name', validated.school_affiliation)
    .limit(1)
    .maybeSingle()

  if (schoolRow?.id) {
    await supabase.from('school_enrollments').upsert(
      { school_id: schoolRow.id, user_id: user.id, enrolled_at: now },
      { onConflict: 'school_id,user_id', ignoreDuplicates: true }
    )
  }

  // Resolve each course by code and create course enrollments
  const courseIds: string[] = []
  for (const code of validated.course_codes) {
    const { data: courseRow } = await supabase
      .from('courses')
      .select('id')
      .eq('code', code)
      .limit(1)
      .maybeSingle()
    if (courseRow?.id) courseIds.push(courseRow.id)
  }

  if (courseIds.length > 0) {
    const enrollments = courseIds.map((course_id) => ({
      course_id,
      user_id: user.id,
      enrolled_at: now,
    }))
    await supabase.from('course_enrollments').upsert(enrollments, {
      onConflict: 'course_id,user_id',
      ignoreDuplicates: true,
    })
  }

  return json(updated)
})
