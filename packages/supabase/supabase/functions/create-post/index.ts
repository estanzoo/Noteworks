import { requireAuth } from '../_shared/auth.ts'
import { corsResponse, json, errorResponse } from '../_shared/cors.ts'

const MAX_TITLE = 255
const MAX_BODY = 10_000
const MAX_ATTACHMENTS = 10
const MAX_HASHTAGS = 20

type PostKind = 'note' | 'study_questions' | 'discussions'
const POST_KINDS: readonly PostKind[] = ['note', 'study_questions', 'discussions'] as const

interface ValidatedInput {
  title: string
  body: string
  visibility: 'public' | 'private'
  course_id: string | null
  post_kind: PostKind
  attachment_note_ids: string[]
  media_paths: string[]
  hashtags: string[]
}

function validate(raw: unknown): ValidatedInput | Response {
  if (raw == null || typeof raw !== 'object' || Array.isArray(raw)) {
    return errorResponse('Validation failed', 'JSON body required', 400)
  }
  const o = raw as Record<string, unknown>
  const errors: Record<string, string> = {}

  const title = typeof o.title === 'string' ? o.title.trim() : ''
  if (!title) errors.title = 'Title is required'
  else if (title.length > MAX_TITLE) errors.title = `Title must be at most ${MAX_TITLE} characters`

  const body = typeof o.body === 'string' ? o.body.trim() : ''
  if (!body) errors.body = 'Body is required'
  else if (body.length > MAX_BODY) errors.body = `Body must be at most ${MAX_BODY} characters`

  const visibility = o.visibility === 'private' ? 'private' as const : 'public' as const

  const courseId = typeof o.course_id === 'string' ? o.course_id.trim() : null

  // post_kind: defaults to 'discussions' to match the mock's pre-selected pill.
  let postKind: PostKind = 'discussions'
  if (typeof o.post_kind === 'string') {
    const candidate = o.post_kind.trim() as PostKind
    if (POST_KINDS.includes(candidate)) postKind = candidate
    else errors.post_kind = `post_kind must be one of: ${POST_KINDS.join(', ')}`
  }

  let mediaPaths: string[] = []
  if (Array.isArray(o.media_paths)) {
    mediaPaths = o.media_paths
      .filter((v): v is string => typeof v === 'string' && v.trim().length > 0)
      .map(p => p.trim())
    if (mediaPaths.length > MAX_ATTACHMENTS) {
      errors.media_paths = `At most ${MAX_ATTACHMENTS} media files allowed`
    }
  }

  let attachmentNoteIds: string[] = []
  if (Array.isArray(o.attachment_note_ids)) {
    attachmentNoteIds = o.attachment_note_ids.filter((v): v is string => typeof v === 'string')
    if (attachmentNoteIds.length > MAX_ATTACHMENTS) {
      errors.attachment_note_ids = `At most ${MAX_ATTACHMENTS} attachments allowed`
    }
  }

  let hashtags: string[] = []
  if (Array.isArray(o.hashtags)) {
    hashtags = o.hashtags
      .filter((v): v is string => typeof v === 'string')
      .map(h => h.toLowerCase().replace(/^#/, '').trim())
      .filter(h => h.length > 0)
    if (hashtags.length > MAX_HASHTAGS) {
      errors.hashtags = `At most ${MAX_HASHTAGS} hashtags allowed`
    }
  }

  if (Object.keys(errors).length > 0) {
    return errorResponse('Validation failed', 'Invalid input', 400, errors)
  }

  return {
    title,
    body,
    visibility,
    course_id: courseId || null,
    post_kind: postKind,
    attachment_note_ids: attachmentNoteIds,
    media_paths: mediaPaths,
    hashtags,
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

  if (!validated.course_id && validated.attachment_note_ids.length > 0) {
    const { data: firstNote, error: noteErr } = await supabase
      .from('notes')
      .select('course_id')
      .eq('id', validated.attachment_note_ids[0])
      .eq('user_id', user.id)
      .maybeSingle()
    if (noteErr) return errorResponse('Query failed', noteErr.message, 500)
    validated.course_id = firstNote?.course_id ?? null
  }

  // Verify course exists if provided
  if (validated.course_id) {
    const { data: course, error: courseErr } = await supabase
      .from('courses')
      .select('id')
      .eq('id', validated.course_id)
      .maybeSingle()
    if (courseErr) return errorResponse('Query failed', courseErr.message, 500)
    if (!course) return errorResponse('Not found', `Course ${validated.course_id} does not exist`, 404)
  }

  // Insert the post
  const { data: post, error: postErr } = await supabase
    .from('posts')
    .insert({
      user_id: user.id,
      title: validated.title,
      body: validated.body,
      visibility: validated.visibility,
      course_id: validated.course_id,
      post_kind: validated.post_kind,
    })
    .select()
    .single()

  if (postErr) return errorResponse('Insert failed', postErr.message, 500)

  // Insert attachments
  if (validated.attachment_note_ids.length > 0) {
    const rows = validated.attachment_note_ids.map(nid => ({ post_id: post.id, note_id: nid }))
    const { error: attErr } = await supabase.from('post_attachments').insert(rows)
    if (attErr) {
      console.error('Attachment insert failed:', attErr.message)
    }
  }

  // Persist image attachments uploaded ahead of time via upload-post-media.
  // The client passes back the storage path returned by that endpoint.
  if (validated.media_paths.length > 0) {
    const rows = validated.media_paths.map(path => ({
      post_id: post.id,
      kind: 'image' as const,
      storage_path: path,
    }))
    const { error: mediaErr } = await supabase.from('post_media').insert(rows)
    if (mediaErr) {
      console.error('post_media insert failed:', mediaErr.message)
    }
  }

  // Upsert hashtags and link (batched — 2 queries instead of N*3)
  const hashtagNames: string[] = []
  if (validated.hashtags.length > 0) {
    const { data: tags, error: upsertErr } = await supabase
      .from('hashtags')
      .upsert(
        validated.hashtags.map(name => ({ name })),
        { onConflict: 'name', ignoreDuplicates: false }
      )
      .select('id, name')

    if (!upsertErr && tags && tags.length > 0) {
      const links = tags.map(t => ({ post_id: post.id, hashtag_id: t.id }))
      const { error: linkErr } = await supabase.from('post_hashtags').insert(links)
      if (!linkErr) hashtagNames.push(...tags.map(t => t.name))
    }
  }

  return json({
    id: post.id,
    user_id: post.user_id,
    title: post.title,
    body: post.body,
    visibility: post.visibility,
    course_id: post.course_id,
    post_kind: post.post_kind,
    likes_count: 0,
    comments_count: 0,
    hashtags: hashtagNames,
    attachments: validated.attachment_note_ids,
    media_paths: validated.media_paths,
    created_at: post.created_at,
    updated_at: post.updated_at,
  }, 201)
})
