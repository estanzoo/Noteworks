// Edge function for the Profile → Feedback section. Validates the
// caller's payload and inserts a row into `public.feedback`. Photos
// are NOT uploaded here — the client can ship `media_paths[]` after a
// separate upload pass once we add the bucket. For now we accept and
// persist whatever paths the client passes through (empty by default).

import { requireAuth } from '../_shared/auth.ts'
import { corsResponse, json, errorResponse } from '../_shared/cors.ts'

const MAX_TITLE = 200
const MAX_BODY = 5_000
const MAX_AREA_OTHER = 120
const MAX_EMAIL = 320

const VALID_TYPES = ['Bug', 'UX', 'Idea', 'Performance', 'Love it'] as const
const VALID_AREAS = ['Home', 'Library', 'Community', 'Note Editor', 'Profile', 'Other'] as const
const VALID_PRIORITIES = ['Minor', 'Major', 'Blocker'] as const

type FeedbackType = (typeof VALID_TYPES)[number]
type FeedbackArea = (typeof VALID_AREAS)[number]
type FeedbackPriority = (typeof VALID_PRIORITIES)[number]

interface ValidBody {
  feedback_type: FeedbackType
  area: FeedbackArea
  area_other: string | null
  priority: FeedbackPriority
  title: string
  body: string
  follow_up_enabled: boolean
  contact_email: string | null
  media_paths: string[]
  app_version: string | null
  device_info: Record<string, unknown> | null
}

function validate(raw: unknown): ValidBody | Response {
  if (raw == null || typeof raw !== 'object' || Array.isArray(raw)) {
    return errorResponse('Validation failed', 'JSON body required', 400)
  }
  const o = raw as Record<string, unknown>
  const errors: Record<string, string> = {}

  const ftype = typeof o.feedback_type === 'string' ? o.feedback_type.trim() : ''
  if (!VALID_TYPES.includes(ftype as FeedbackType)) {
    errors.feedback_type = `feedback_type must be one of: ${VALID_TYPES.join(', ')}`
  }

  const area = typeof o.area === 'string' ? o.area.trim() : ''
  if (!VALID_AREAS.includes(area as FeedbackArea)) {
    errors.area = `area must be one of: ${VALID_AREAS.join(', ')}`
  }

  const areaOtherRaw = typeof o.area_other === 'string' ? o.area_other.trim() : ''
  if (area === 'Other' && areaOtherRaw.length === 0) {
    errors.area_other = 'area_other is required when area is "Other"'
  } else if (areaOtherRaw.length > MAX_AREA_OTHER) {
    errors.area_other = `area_other must be at most ${MAX_AREA_OTHER} characters`
  }

  const priority = typeof o.priority === 'string' ? o.priority.trim() : ''
  if (!VALID_PRIORITIES.includes(priority as FeedbackPriority)) {
    errors.priority = `priority must be one of: ${VALID_PRIORITIES.join(', ')}`
  }

  const title = typeof o.title === 'string' ? o.title.trim() : ''
  if (!title) errors.title = 'title is required'
  else if (title.length > MAX_TITLE) errors.title = `title must be at most ${MAX_TITLE} characters`

  const body = typeof o.body === 'string' ? o.body.trim() : ''
  if (!body) errors.body = 'body is required'
  else if (body.length > MAX_BODY) errors.body = `body must be at most ${MAX_BODY} characters`

  const followUp = Boolean(o.follow_up_enabled)

  const emailRaw = typeof o.contact_email === 'string' ? o.contact_email.trim() : ''
  let contactEmail: string | null = null
  if (followUp && emailRaw.length > 0) {
    if (emailRaw.length > MAX_EMAIL || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(emailRaw)) {
      errors.contact_email = 'contact_email must be a valid email address'
    } else {
      contactEmail = emailRaw.toLowerCase()
    }
  }

  let mediaPaths: string[] = []
  if (Array.isArray(o.media_paths)) {
    mediaPaths = o.media_paths
      .filter((v): v is string => typeof v === 'string' && v.trim().length > 0)
      .map(p => p.trim())
    if (mediaPaths.length > 10) {
      errors.media_paths = 'At most 10 media files allowed'
    }
  }

  const appVersion = typeof o.app_version === 'string' && o.app_version.trim().length > 0
    ? o.app_version.trim().slice(0, 120)
    : null

  let deviceInfo: Record<string, unknown> | null = null
  if (o.device_info && typeof o.device_info === 'object' && !Array.isArray(o.device_info)) {
    deviceInfo = o.device_info as Record<string, unknown>
  }

  if (Object.keys(errors).length > 0) {
    return errorResponse('Validation failed', 'Invalid input', 400, errors)
  }

  return {
    feedback_type: ftype as FeedbackType,
    area: area as FeedbackArea,
    area_other: area === 'Other' ? areaOtherRaw : null,
    priority: priority as FeedbackPriority,
    title,
    body,
    follow_up_enabled: followUp,
    contact_email: contactEmail,
    media_paths: mediaPaths,
    app_version: appVersion,
    device_info: deviceInfo,
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

  let raw: unknown
  try {
    raw = await req.json()
  } catch {
    return errorResponse('Bad request', 'Invalid JSON body', 400)
  }

  const validated = validate(raw)
  if (validated instanceof Response) return validated

  const { data: inserted, error: insertErr } = await supabase
    .from('feedback')
    .insert({
      user_id: user.id,
      feedback_type: validated.feedback_type,
      area: validated.area,
      area_other: validated.area_other,
      priority: validated.priority,
      title: validated.title,
      body: validated.body,
      follow_up_enabled: validated.follow_up_enabled,
      contact_email: validated.contact_email,
      media_paths: validated.media_paths,
      app_version: validated.app_version,
      device_info: validated.device_info,
    })
    .select()
    .single()

  if (insertErr) return errorResponse('Insert failed', insertErr.message, 500)

  return json({
    id: inserted.id,
    status: inserted.status,
    created_at: inserted.created_at,
  }, 201)
})
