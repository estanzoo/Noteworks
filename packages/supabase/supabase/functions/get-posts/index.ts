import { requireAuth } from '../_shared/auth.ts'
import { corsResponse, json, errorResponse } from '../_shared/cors.ts'

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return corsResponse()
  if (req.method !== 'GET') {
    return errorResponse('Method not allowed', 'Use GET', 405)
  }

  const auth = await requireAuth(req)
  if (auth instanceof Response) return auth
  const { supabase, user } = auth

  const url = new URL(req.url)
  const cursor = url.searchParams.get('cursor')
  const limit = Math.min(50, Math.max(1, Number(url.searchParams.get('limit') ?? 20)))
  const userId = url.searchParams.get('user_id')
  const hashtag = url.searchParams.get('hashtag')
  const courseId = url.searchParams.get('course_id')
  const likedByMe = url.searchParams.get('liked_by_me') === 'true'
  const includeOwnPrivate = url.searchParams.get('include_own_private') === 'true'

  // Build the base query depending on which filter mode we're in
  // We need to use raw SQL-like approach for the liked_by_me join and hashtag join
  // But supabase-js can handle most of this with filters

  let query = supabase
    .from('posts')
    .select(`
      id, user_id, title, body, visibility, course_id,
      likes_count, comments_count, created_at, updated_at,
      author:users!posts_user_id_fkey(id, name)
    `)
    .is('deleted_at', null)
    .order('created_at', { ascending: false })
    .limit(limit + 1) // fetch one extra to determine next_cursor

  if (cursor) {
    query = query.lt('created_at', cursor)
  }

  // Visibility filtering
  if (userId) {
    query = query.eq('user_id', userId)
    if (userId === user.id && includeOwnPrivate) {
      // Show all (public + private) for the requesting user
    } else {
      query = query.eq('visibility', 'public')
    }
  } else {
    query = query.eq('visibility', 'public')
  }

  if (courseId) {
    query = query.eq('course_id', courseId)
  }

  // For hashtag filtering, get post IDs first
  if (hashtag) {
    const { data: tagRow } = await supabase
      .from('hashtags')
      .select('id')
      .eq('name', hashtag.toLowerCase())
      .maybeSingle()

    if (!tagRow) {
      return json({ data: [], next_cursor: null })
    }

    const { data: postHashtags } = await supabase
      .from('post_hashtags')
      .select('post_id')
      .eq('hashtag_id', tagRow.id)

    const postIds = (postHashtags ?? []).map(ph => ph.post_id)
    if (postIds.length === 0) {
      return json({ data: [], next_cursor: null })
    }
    query = query.in('id', postIds)
  }

  // For liked_by_me, get the user's liked post IDs first
  if (likedByMe) {
    const { data: likes } = await supabase
      .from('post_likes')
      .select('post_id')
      .eq('user_id', user.id)

    const likedIds = (likes ?? []).map(l => l.post_id)
    if (likedIds.length === 0) {
      return json({ data: [], next_cursor: null })
    }
    query = query.in('id', likedIds)
  }

  const { data: posts, error: postsErr } = await query

  if (postsErr) return errorResponse('Query failed', postsErr.message, 500)
  if (!posts || posts.length === 0) {
    return json({ data: [], next_cursor: null })
  }

  // Determine pagination
  const hasMore = posts.length > limit
  const sliced = hasMore ? posts.slice(0, limit) : posts
  const nextCursor = hasMore ? sliced[sliced.length - 1].created_at : null

  const postIds = sliced.map(p => p.id)

  // Batch-fetch hashtags for these posts
  const { data: phRows } = await supabase
    .from('post_hashtags')
    .select('post_id, hashtag:hashtags(name)')
    .in('post_id', postIds)

  const hashtagsByPost: Record<string, string[]> = {}
  for (const row of phRows ?? []) {
    const tag = row.hashtag as unknown as { name: string } | null
    if (tag) {
      if (!hashtagsByPost[row.post_id]) hashtagsByPost[row.post_id] = []
      hashtagsByPost[row.post_id].push(tag.name)
    }
  }

  // Batch-fetch attachments with PDF metadata
  const { data: attRows } = await supabase
    .from('post_attachments')
    .select('post_id, note_id, note:notes(title, metadata)')
    .in('post_id', postIds)

  const attachmentsByPost: Record<string, { note_id: string; title: string; has_pdf: boolean; pdf_filename: string | null }[]> = {}
  for (const row of attRows ?? []) {
    const note = row.note as unknown as { title: string; metadata: Record<string, unknown> | null } | null
    const meta = note?.metadata
    if (!attachmentsByPost[row.post_id]) attachmentsByPost[row.post_id] = []
    attachmentsByPost[row.post_id].push({
      note_id: row.note_id,
      title: note?.title ?? 'Untitled',
      has_pdf: !!(meta?.pdf_path),
      pdf_filename: (meta?.pdf_filename as string) ?? null,
    })
  }

  // Batch-check which posts the current user has liked
  const { data: userLikes } = await supabase
    .from('post_likes')
    .select('post_id')
    .eq('user_id', user.id)
    .in('post_id', postIds)

  const likedSet = new Set((userLikes ?? []).map(l => l.post_id))

  const data = sliced.map(p => {
    const author = p.author as unknown as { id: string; name: string | null } | null
    return {
      id: p.id,
      user_id: p.user_id,
      author: author ?? { id: p.user_id, name: null },
      title: p.title,
      body: p.body,
      visibility: p.visibility,
      course_id: p.course_id,
      likes_count: p.likes_count,
      comments_count: p.comments_count,
      has_liked: likedSet.has(p.id),
      hashtags: hashtagsByPost[p.id] ?? [],
      attachments: attachmentsByPost[p.id] ?? [],
      created_at: p.created_at,
      updated_at: p.updated_at,
    }
  })

  return json({ data, next_cursor: nextCursor })
})
