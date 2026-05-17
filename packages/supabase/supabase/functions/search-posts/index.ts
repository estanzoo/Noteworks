// Substring search over public community posts.
//
// Matches `q` (case-insensitive, substring) against:
//   - posts.title
//   - posts.body
//   - the title of any note attached via post_attachments
//
// Response shape mirrors get-posts: `{ posts: [...], next_cursor }`.
// Scope:
//   - public posts only (visibility = 'public', deleted_at is null)
//   - cursor pagination is by created_at (DESC), same as the main feed
//   - results are capped at 50 per page
//
// Implementation note: we run two queries and union them in JS instead
// of using PostgREST's `.or()` with `id.in.(uuid1,uuid2,...)`. The OR
// approach works but is fragile when the embedded UUID list grows
// (PostgREST tokenizes commas inside parentheses correctly today, but
// the URL also gets long enough to trigger 414s past a few hundred
// matches). Two small queries + dedupe is simpler and predictable.

import { requireAuth } from '../_shared/auth.ts'
import { corsResponse, json, errorResponse } from '../_shared/cors.ts'
import { displayName } from '../_shared/author.ts'

/// Escape `%`, `_`, and `\` so the user-supplied query is treated as a
/// pure substring under ILIKE. Without this, typing `100%_off` would
/// produce a wildcard pattern instead of matching the literal string.
function escapeLike(raw: string): string {
  return raw.replace(/[\\%_]/g, (ch) => `\\${ch}`)
}

interface PostRow {
  id: string
  user_id: string
  title: string
  body: string
  visibility: string
  course_id: string | null
  post_kind: string
  likes_count: number
  comments_count: number
  created_at: string
  updated_at: string
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return corsResponse()
  if (req.method !== 'GET') {
    return errorResponse('Method not allowed', 'Use GET', 405)
  }

  const auth = await requireAuth(req)
  if (auth instanceof Response) return auth
  const { supabase, user } = auth

  const url = new URL(req.url)
  const rawQ = (url.searchParams.get('q') ?? '').trim()
  if (rawQ.length < 1) {
    return errorResponse('Validation failed', 'Query param q is required', 400)
  }
  if (rawQ.length > 200) {
    return errorResponse('Validation failed', 'Query param q must be 200 chars or fewer', 400)
  }

  const cursor = url.searchParams.get('cursor')
  const limit = Math.min(50, Math.max(1, Number(url.searchParams.get('limit') ?? 20)))
  const pattern = `%${escapeLike(rawQ)}%`

  // Query 1: posts whose title or body matches.
  let titleBodyQuery = supabase
    .from('posts')
    .select(`
      id, user_id, title, body, visibility, course_id, post_kind,
      likes_count, comments_count, created_at, updated_at
    `)
    .is('deleted_at', null)
    .eq('visibility', 'public')
    .or(`title.ilike.${pattern},body.ilike.${pattern}`)
    .order('created_at', { ascending: false })
    .limit((limit + 1) * 2)

  if (cursor) {
    titleBodyQuery = titleBodyQuery.lt('created_at', cursor)
  }

  // Query 2: posts whose attached note titles match. We pre-fetch the
  // post_ids via a join on post_attachments -> notes, then fetch those
  // posts (with the same filters) so the response rows have the full
  // shape needed for the feed UI.
  const { data: attachMatches, error: attachErr } = await supabase
    .from('post_attachments')
    .select('post_id, note:notes!inner(title)')
    .ilike('note.title', pattern)
    .limit(500)

  if (attachErr) {
    return errorResponse('Query failed', attachErr.message, 500)
  }

  const attachedPostIds = Array.from(
    new Set((attachMatches ?? []).map((row) => row.post_id as string)),
  )

  const [titleBodyRes, attachedRes] = await Promise.all([
    titleBodyQuery,
    attachedPostIds.length > 0
      ? (() => {
          let q = supabase
            .from('posts')
            .select(`
              id, user_id, title, body, visibility, course_id, post_kind,
              likes_count, comments_count, created_at, updated_at
            `)
            .is('deleted_at', null)
            .eq('visibility', 'public')
            .in('id', attachedPostIds)
            .order('created_at', { ascending: false })
            .limit((limit + 1) * 2)
          if (cursor) q = q.lt('created_at', cursor)
          return q
        })()
      : Promise.resolve({ data: [] as PostRow[], error: null }),
  ])

  if (titleBodyRes.error) {
    return errorResponse('Query failed', titleBodyRes.error.message, 500)
  }
  if (attachedRes.error) {
    return errorResponse('Query failed', attachedRes.error.message, 500)
  }

  // Merge + dedupe by id, then sort by created_at DESC and clip to
  // limit+1 (so we can derive next_cursor). The cap is generous enough
  // (2*(limit+1) per branch) that the merged top-N is correct as long
  // as the underlying tables aren't pathologically lopsided.
  const merged = new Map<string, PostRow>()
  for (const row of (titleBodyRes.data ?? []) as PostRow[]) {
    merged.set(row.id, row)
  }
  for (const row of (attachedRes.data ?? []) as PostRow[]) {
    if (!merged.has(row.id)) merged.set(row.id, row)
  }
  const allMatches = Array.from(merged.values()).sort((a, b) =>
    a.created_at < b.created_at ? 1 : a.created_at > b.created_at ? -1 : 0,
  )

  const hasMore = allMatches.length > limit
  const sliced = hasMore ? allMatches.slice(0, limit) : allMatches
  const nextCursor = hasMore ? sliced[sliced.length - 1].created_at : null

  if (sliced.length === 0) {
    return json({ posts: [], next_cursor: null })
  }

  const postIds = sliced.map((p) => p.id)

  // Batch-fetch hashtags for these posts.
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

  // Batch-fetch attachments with PDF metadata.
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

  // Which posts has the current user liked?
  const { data: userLikes } = await supabase
    .from('post_likes')
    .select('post_id')
    .eq('user_id', user.id)
    .in('post_id', postIds)

  const likedSet = new Set((userLikes ?? []).map((l) => l.post_id))

  // Authors — fetched separately via `user_profiles` to dodge the
  // per-user RLS on `public.users` (otherwise the embedded join
  // returns null for every author who isn't the caller, and the
  // client falls back to "Student").
  const authorIds = Array.from(new Set(sliced.map(p => p.user_id)))
  const authorById = new Map<string, { id: string; name: string; avatar_url: string | null }>()
  if (authorIds.length > 0) {
    const { data: profiles } = await supabase
      .from('user_profiles')
      .select('id, name, avatar_url')
      .in('id', authorIds)
    for (const row of profiles ?? []) {
      authorById.set(row.id as string, {
        id: row.id as string,
        name: displayName(row.name as string | null, null),
        avatar_url: (row.avatar_url as string | null) ?? null,
      })
    }
  }

  // Image / video media
  const { data: mediaRows } = await supabase
    .from('post_media')
    .select('post_id, kind, storage_path')
    .in('post_id', postIds)

  const mediaByPost: Record<string, { kind: string; url: string }[]> = {}
  for (const row of mediaRows ?? []) {
    const { data: pub } = supabase.storage.from('post-media').getPublicUrl(row.storage_path as string)
    if (!mediaByPost[row.post_id as string]) mediaByPost[row.post_id as string] = []
    mediaByPost[row.post_id as string].push({ kind: row.kind as string, url: pub.publicUrl })
  }

  const responsePosts = sliced.map((p) => {
    const author = authorById.get(p.user_id)
      ?? { id: p.user_id, name: 'Student', avatar_url: null }
    return {
      id: p.id,
      user_id: p.user_id,
      author,
      title: p.title,
      body: p.body,
      visibility: p.visibility,
      course_id: p.course_id,
      post_kind: p.post_kind,
      likes_count: p.likes_count,
      comments_count: p.comments_count,
      has_liked: likedSet.has(p.id),
      hashtags: hashtagsByPost[p.id] ?? [],
      attachments: attachmentsByPost[p.id] ?? [],
      media: mediaByPost[p.id] ?? [],
      created_at: p.created_at,
      updated_at: p.updated_at,
    }
  })

  return json({ posts: responsePosts, next_cursor: nextCursor })
})
