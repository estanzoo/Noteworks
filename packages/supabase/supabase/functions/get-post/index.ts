import { requireAuth } from '../_shared/auth.ts'
import { corsResponse, json, errorResponse } from '../_shared/cors.ts'
import { displayName, nullIfBlank } from '../_shared/author.ts'
import { resolvePostMediaUrls } from '../_shared/post-media-urls.ts'

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return corsResponse()
  if (req.method !== 'GET') {
    return errorResponse('Method not allowed', 'Use GET', 405)
  }

  const auth = await requireAuth(req)
  if (auth instanceof Response) return auth
  const { supabase, user } = auth

  const url = new URL(req.url)
  const postId = url.searchParams.get('post_id')
  if (!postId) {
    return errorResponse('Validation failed', 'Query param post_id is required', 400)
  }

  const { data: post, error: postErr } = await supabase
    .from('posts')
    .select(`
      id, user_id, title, body, visibility, course_id, post_kind,
      likes_count, comments_count, created_at, updated_at, deleted_at
    `)
    .eq('id', postId)
    .maybeSingle()

  if (postErr) return errorResponse('Query failed', postErr.message, 500)
  if (!post) return errorResponse('Not found', 'Post not found', 404)

  if (post.deleted_at && post.user_id !== user.id) {
    return errorResponse('Not found', 'Post not found', 404)
  }
  if (post.visibility === 'private' && post.user_id !== user.id) {
    return errorResponse('Forbidden', 'This post is private', 403)
  }

  // Fetch hashtags
  const { data: phRows } = await supabase
    .from('post_hashtags')
    .select('hashtag:hashtags(name)')
    .eq('post_id', postId)

  const hashtags = (phRows ?? [])
    .map(r => (r.hashtag as unknown as { name: string } | null)?.name)
    .filter((n): n is string => !!n)

  // Fetch attachments with PDF metadata
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

  // Check if current user liked
  const { data: likeRow } = await supabase
    .from('post_likes')
    .select('post_id')
    .eq('post_id', postId)
    .eq('user_id', user.id)
    .maybeSingle()

  // Image / video attachments
  const { data: mediaRows } = await supabase
    .from('post_media')
    .select('kind, storage_path')
    .eq('post_id', postId)

  const media = await resolvePostMediaUrls(
    (mediaRows ?? []).map(row => ({
      kind: row.kind as string,
      storage_path: row.storage_path as string,
    })),
  )

  // Author lookup via the `user_profiles` view — bypasses the
  // per-user RLS on `public.users` so we always get the real name +
  // avatar, not "Student" for everyone else.
  const { data: profileRow } = await supabase
    .from('user_profiles')
    .select('id, name, avatar_url, school_affiliation, major')
    .eq('id', post.user_id)
    .maybeSingle()

  const author = profileRow
    ? {
        id: profileRow.id as string,
        name: displayName(profileRow.name as string | null, null),
        avatar_url: (profileRow.avatar_url as string | null) ?? null,
        school: nullIfBlank(profileRow.school_affiliation as string | null),
        major: nullIfBlank(profileRow.major as string | null),
      }
    : { id: post.user_id, name: 'Student', avatar_url: null, school: null, major: null }

  return json({
    id: post.id,
    user_id: post.user_id,
    author,
    title: post.title,
    body: post.body,
    visibility: post.visibility,
    course_id: post.course_id,
    post_kind: post.post_kind,
    likes_count: post.likes_count,
    comments_count: post.comments_count,
    has_liked: !!likeRow,
    hashtags,
    attachments,
    media,
    created_at: post.created_at,
    updated_at: post.updated_at,
  })
})
