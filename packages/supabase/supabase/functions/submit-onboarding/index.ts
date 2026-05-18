import { requireAuth } from '../_shared/auth.ts'
import { corsResponse, json, errorResponse } from '../_shared/cors.ts'

const MAX_NAME = 255
const MAX_SCHOOL = 255
const MAX_MAJOR = 255
const MAX_EMAIL = 255
const MAX_COURSE_CODE = 50
const MAX_COURSE_CODES = 50
const MAX_INTEREST = 50
const MAX_INTERESTS = 50
const MAX_BIO = 280
const MIN_GRADUATION_YEAR = 2000
const MAX_GRADUATION_YEAR = 2100

const EMAIL_REGEX = /^[^\s@]+@[^\s@]+\.[^\s@]+$/

type ValidBody = {
  name: string
  year_of_graduation: number
  school_affiliation: string
  school_id: string | null
  school_email: string
  course_codes: string[]
  /// Free-form topics the user picked on the "Any Field of Interests?"
  /// step. Stored in its own column (`users.interests`) — distinct from
  /// `course_codes`, which is reserved for registrar-grade identifiers.
  interests: string[]
  major: string | null
  bio: string | null
}

function validate(body: unknown): ValidBody | { errors: Record<string, string> } {
  if (body == null || typeof body !== 'object' || Array.isArray(body)) {
    return {
      errors: {
        body:
          'JSON body with name, year_of_graduation, school_affiliation, school_email, course_codes required',
      },
    }
  }
  const o = body as Record<string, unknown>
  const name = typeof o.name === 'string' ? o.name.trim() : ''
  const year_of_graduation = typeof o.year_of_graduation === 'number' ? o.year_of_graduation : NaN
  const school_affiliation =
    typeof o.school_affiliation === 'string' ? o.school_affiliation.trim() : ''
  const school_id =
    typeof o.school_id === 'string' && /^[0-9a-f-]{36}$/i.test(o.school_id) ? o.school_id : null
  const school_email = typeof o.school_email === 'string' ? o.school_email.trim() : ''
  const majorRaw = typeof o.major === 'string' ? o.major.trim() : ''
  // Bio is optional. We accept null / missing as "no change" by sending
  // null through; the upsert below leaves the column at whatever value
  // was previously stored when explicitly null.
  const bioProvided = Object.prototype.hasOwnProperty.call(o, 'bio')
  const bioRaw = typeof o.bio === 'string' ? o.bio.trim() : ''

  let course_codes: string[] = []
  if (Array.isArray(o.course_codes)) {
    course_codes = o.course_codes
      .filter((c): c is string => typeof c === 'string')
      .map((c) => c.trim())
      .filter((c) => c.length > 0)
  }

  let interests: string[] = []
  if (Array.isArray(o.interests)) {
    interests = o.interests
      .filter((c): c is string => typeof c === 'string')
      .map((c) => c.trim())
      .filter((c) => c.length > 0)
  }

  const errors: Record<string, string> = {}

  if (name.length === 0) errors.name = 'Name is required'
  else if (name.length > MAX_NAME) errors.name = `Name must be at most ${MAX_NAME} characters`

  if (isNaN(year_of_graduation) || !Number.isInteger(year_of_graduation))
    errors.year_of_graduation = 'Year of graduation is required and must be an integer'
  else if (year_of_graduation < MIN_GRADUATION_YEAR || year_of_graduation > MAX_GRADUATION_YEAR)
    errors.year_of_graduation = `Year of graduation must be between ${MIN_GRADUATION_YEAR} and ${MAX_GRADUATION_YEAR}`

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

  if (interests.length > MAX_INTERESTS)
    errors.interests = `At most ${MAX_INTERESTS} interests allowed`
  for (let i = 0; i < interests.length; i++) {
    if (interests[i].length > MAX_INTEREST) {
      errors[`interests[${i}]`] = `Interest must be at most ${MAX_INTEREST} characters`
      break
    }
  }

  if (majorRaw.length > MAX_MAJOR) {
    errors.major = `Major must be at most ${MAX_MAJOR} characters`
  }
  const major = majorRaw.length > 0 ? majorRaw : null

  if (bioProvided && bioRaw.length > MAX_BIO) {
    errors.bio = `Bio must be at most ${MAX_BIO} characters`
  }
  // `null` here means "caller didn't send a bio key, leave whatever's in
  // the column alone". An explicit empty string clears the field.
  const bio: string | null = bioProvided ? (bioRaw.length > 0 ? bioRaw : '') : null

  if (Object.keys(errors).length > 0) return { errors }
  return {
    name,
    year_of_graduation,
    school_affiliation,
    school_id,
    school_email,
    course_codes,
    interests,
    major,
    bio,
  }
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

  // Upsert (not just update) so the row self-heals if `public.users` is
  // somehow missing for this authenticated user — e.g. an Apple sign-in
  // whose `handle_new_user` trigger silently failed at signup time
  // (this used to surface as "User profile not found" on the Interests
  // step). The RLS INSERT policy on `public.users` is open and the
  // SELECT/UPDATE policies both gate on `auth.uid() = id`, so the
  // synthetic INSERT can only ever create a row for the caller.
  const upsertRow: Record<string, unknown> = {
    id: user.id,
    email: user.email ?? `${user.id}@noreply.local`,
    name: validated.name,
    year_of_graduation: validated.year_of_graduation,
    school_affiliation: validated.school_affiliation,
    school_email: validated.school_email,
    course_codes: validated.course_codes,
    interests: validated.interests,
    major: validated.major,
    onboarding_completed_at: now,
    updated_at: now,
  }
  // Only forward `bio` to the upsert when the caller explicitly included
  // it on the payload. The onboarding flow itself never sends a bio (the
  // field doesn't exist on those steps); the Profile → About You editor
  // reuses this same endpoint and is the only caller that sets it.
  if (validated.bio !== null) {
    upsertRow.bio = validated.bio
  }

  const { data: updated, error: updateError } = await supabase
    .from('users')
    .upsert(upsertRow, { onConflict: 'id' })
    .select()
    .single()

  if (updateError) {
    return errorResponse('Update failed', updateError.message, 500)
  }

  // Resolve school and create enrollment — prefer explicit school_id, fall back to name match
  let resolvedSchoolId = validated.school_id
  if (!resolvedSchoolId) {
    const { data: schoolRow } = await supabase
      .from('schools')
      .select('id')
      .ilike('name', validated.school_affiliation)
      .limit(1)
      .maybeSingle()
    resolvedSchoolId = schoolRow?.id ?? null
  }

  if (resolvedSchoolId) {
    await supabase.from('school_enrollments').upsert(
      { school_id: resolvedSchoolId, user_id: user.id, enrolled_at: now },
      { onConflict: 'school_id,user_id', ignoreDuplicates: true }
    )
  }

  // Resolve all courses by code in a single query
  const courseIds: string[] = []
  if (validated.course_codes.length > 0) {
    const { data: courseRows } = await supabase
      .from('courses')
      .select('id')
      .in('code', validated.course_codes)
    if (courseRows) courseIds.push(...courseRows.map(r => r.id))
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
