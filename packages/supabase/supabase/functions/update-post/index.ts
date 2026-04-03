import { requireAuth } from '../_shared/auth.ts'
import { corsResponse, json, errorResponse } from '../_shared/cors.ts'

const MAX_TITLE = 255
const MAX_BODY = 10_000
const MAX_ATTACHMENTS = 10
const MAX_HASHTAGS = 20

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return corsResponse()
  if (req.method !== 'PATCH') {
    return errorResponse('Method not allowed', 'Use PATCH', 405)
  }

  const auth = await requireAuth(req)
  if (auth instanceof Response) return auth
  const { supabase, user } = auth

  let body: Record<string, unknown>
  try {
    body = await req.json()
  } catch {
    return errorResponse('Bad request', 'Invalid JSON body', 400)
  }

  const postId = typeof body.post_id === 'string' ? body.post_id.trim() : ''
  if (!postId) return errorResponse('Validation failed', 'post_id is required', 400)

  // Verify ownership
  const { data: existing, error: fetchErr } = await supabase
    .from('posts')
    .select('id, user_id, deleted_at')
    .eq('id', postId)
    .maybeSingle()

  if (fetchErr) return errorResponse('Query failed', fetchErr.message, 500)
  if (!existing) return errorResponse('Not found', 'Post not found', 404)
  if (existing.deleted_at) return errorResponse('Not found', 'Post has been deleted', 404)
  if (existing.user_id !== user.id) return errorResponse('Forbidden', 'You can only edit your own posts', 403)

  // Build update payload
  const errors: Record<string, string> = {}
  const updates: Record<string, unknown> = {}

  if (body.title !== undefined) {
    const title = typeof body.title === 'string' ? body.title.trim() : ''
    if (!title) errors.title = 'Title cannot be empty'
    else if (title.length > MAX_TITLE) errors.title = `Title must be at most ${MAX_TITLE} characters`
    else updates.title = title
  }

  if (body.body !== undefined) {
    const text = typeof body.body === 'string' ? body.body.trim() : ''
    if (!text) errors.body = 'Body cannot be empty'
    else if (text.length > MAX_BODY) errors.body = `Body must be at most ${MAX_BODY} characters`
    else updates.body = text
  }

  if (body.visibility !== undefined) {
    if (body.visibility !== 'public' && body.visibility !== 'private') {
      errors.visibility = 'Visibility must be "public" or "private"'
    } else {
      updates.visibility = body.visibility
    }
  }

  if (body.course_id !== undefined) {
    if (body.course_id === null) {
      updates.course_id = null
    } else if (typeof body.course_id === 'string') {
      updates.course_id = body.course_id
    }
  }

  if (Object.keys(errors).length > 0) {
    return errorResponse('Validation failed', 'Invalid input', 400, errors)
  }

  // Apply field updates
  if (Object.keys(updates).length > 0) {
    const { error: updateErr } = await supabase
      .from('posts')
      .update(updates)
      .eq('id', postId)

    if (updateErr) return errorResponse('Update failed', updateErr.message, 500)
  }

  // Sync attachments if provided (full replacement)
  if (Array.isArray(body.attachment_note_ids)) {
    const noteIds = (body.attachment_note_ids as unknown[])
      .filter((v): v is string => typeof v === 'string')
    if (noteIds.length > MAX_ATTACHMENTS) {
      return errorResponse('Validation failed', `At most ${MAX_ATTACHMENTS} attachments allowed`, 400)
    }
    await supabase.from('post_attachments').delete().eq('post_id', postId)
    if (noteIds.length > 0) {
      const rows = noteIds.map(nid => ({ post_id: postId, note_id: nid }))
      await supabase.from('post_attachments').insert(rows)
    }
  }

  // Sync hashtags if provided (full replacement)
  if (Array.isArray(body.hashtags)) {
    const names = (body.hashtags as unknown[])
      .filter((v): v is string => typeof v === 'string')
      .map(h => h.toLowerCase().replace(/^#/, '').trim())
      .filter(h => h.length > 0)
    if (names.length > MAX_HASHTAGS) {
      return errorResponse('Validation failed', `At most ${MAX_HASHTAGS} hashtags allowed`, 400)
    }

    await supabase.from('post_hashtags').delete().eq('post_id', postId)

    for (const name of names) {
      const { data: existing } = await supabase
        .from('hashtags')
        .select('id')
        .eq('name', name)
        .maybeSingle()

      let tagId: string
      if (existing) {
        tagId = existing.id
      } else {
        const { data: newTag, error: tagErr } = await supabase
          .from('hashtags')
          .insert({ name })
          .select('id')
          .single()
        if (tagErr || !newTag) continue
        tagId = newTag.id
      }
      await supabase.from('post_hashtags').insert({ post_id: postId, hashtag_id: tagId })
    }
  }

  // Re-fetch the updated post
  const { data: updated, error: refetchErr } = await supabase
    .from('posts')
    .select(`
      id, user_id, title, body, visibility, course_id,
      likes_count, comments_count, created_at, updated_at
    `)
    .eq('id', postId)
    .single()

  if (refetchErr) return errorResponse('Query failed', refetchErr.message, 500)

  // Fetch current hashtags and attachments for response
  const { data: phRows } = await supabase
    .from('post_hashtags')
    .select('hashtag:hashtags(name)')
    .eq('post_id', postId)

  const hashtags = (phRows ?? [])
    .map(r => (r.hashtag as unknown as { name: string } | null)?.name)
    .filter((n): n is string => !!n)

  const { data: attRows } = await supabase
    .from('post_attachments')
    .select('note_id, note:notes(title, metadata)')
    .eq('post_id', postId)

  const attachments = (attRows ?? []).map(r => {
    const note = r.note as unknown as { title: string; metadata: Record<string, unknown> | null } | null
    const meta = note?.metadata
    return {
      note_id: r.note_id,
      title: note?.title ?? 'Untitled',
      has_pdf: !!(meta?.pdf_path),
      pdf_filename: (meta?.pdf_filename as string) ?? null,
    }
  })

  return json({
    ...updated,
    hashtags,
    attachments,
  })
})
