import { requireAuth } from '../_shared/auth.ts'
import { corsResponse, json, errorResponse } from '../_shared/cors.ts'
import { displayName, nullIfBlank } from '../_shared/author.ts'

// Cursor format:
//   When school-prioritized feed is active, the cursor encodes the phase:
//     "school:<created_at>"  -> still paginating through same-school posts
//     "other:<created_at>"   -> paginating through everyone else's posts
//   When school prioritization is not in effect, the cursor is just "<created_at>"
//   for backwards compatibility with older clients.
type Phase = 'school' | 'other'

function parseCursor(raw: string | null): { phase: Phase | null; ts: string | null } {
  if (!raw) return { phase: null, ts: null }
  if (raw.startsWith('school:')) {
    const rest = raw.slice('school:'.length)
    return { phase: 'school', ts: rest.length > 0 ? rest : null }
  }
  if (raw.startsWith('other:')) {
    const rest = raw.slice('other:'.length)
    return { phase: 'other', ts: rest.length > 0 ? rest : null }
  }
  return { phase: null, ts: raw }
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
  const cursorRaw = url.searchParams.get('cursor')
  const limit = Math.min(50, Math.max(1, Number(url.searchParams.get('limit') ?? 20)))
  const userId = url.searchParams.get('user_id')
  const hashtag = url.searchParams.get('hashtag')
  const courseId = url.searchParams.get('course_id')
  const likedByMe = url.searchParams.get('liked_by_me') === 'true'
  const includeOwnPrivate = url.searchParams.get('include_own_private') === 'true'

  const { phase: cursorPhase, ts: cursorTs } = parseCursor(cursorRaw)

  // School-priority ordering only applies to the general feed.
  // When the caller already narrows results by user, liked-by-me, or hashtag,
  // those results are personal/specific enough that re-ordering by college
  // adds no value (and would force extra round-trips).
  const allowSchoolPriority = !userId && !likedByMe && !hashtag

  let schoolMemberIds: string[] | null = null
  if (allowSchoolPriority) {
    const { data: myEnrollment } = await supabase
      .from('school_enrollments')
      .select('school_id')
      .eq('user_id', user.id)
      .limit(1)
      .maybeSingle()

    if (myEnrollment?.school_id) {
      const { data: members } = await supabase
        .from('school_enrollments')
        .select('user_id')
        .eq('school_id', myEnrollment.school_id)

      const ids = (members ?? []).map(m => m.user_id as string)
      if (ids.length > 0) schoolMemberIds = ids
    }
  }

  // Decide which phase we should be querying right now.
  // - If the cursor explicitly names a phase, honor it.
  // - Otherwise, start with "school" if we have school members, else "other".
  let activePhase: Phase = 'school'
  if (cursorPhase) {
    activePhase = cursorPhase
  } else if (!schoolMemberIds) {
    activePhase = 'other'
  }

  // Hashtag pre-resolution. Done up-front so we can short-circuit empty results.
  let hashtagPostIds: string[] | null = null
  if (hashtag) {
    const { data: tagRow } = await supabase
      .from('hashtags')
      .select('id')
      .eq('name', hashtag.toLowerCase())
      .maybeSingle()

    if (!tagRow) {
      return json({ posts: [], next_cursor: null })
    }

    const { data: postHashtags } = await supabase
      .from('post_hashtags')
      .select('post_id')
      .eq('hashtag_id', tagRow.id)

    hashtagPostIds = (postHashtags ?? []).map(ph => ph.post_id as string)
    if (hashtagPostIds.length === 0) {
      return json({ posts: [], next_cursor: null })
    }
  }

  // liked_by_me pre-resolution (same pattern as hashtag).
  let likedPostIds: string[] | null = null
  if (likedByMe) {
    const { data: likes } = await supabase
      .from('post_likes')
      .select('post_id')
      .eq('user_id', user.id)

    likedPostIds = (likes ?? []).map(l => l.post_id as string)
    if (likedPostIds.length === 0) {
      return json({ posts: [], next_cursor: null })
    }
  }

  // Builds a query for a given phase. Phase is ignored when school-priority is off.
  function buildQuery(phase: Phase, phaseCursorTs: string | null, phaseLimit: number) {
    let q = supabase
      .from('posts')
      .select(`
        id, user_id, title, body, visibility, course_id, post_kind,
        likes_count, comments_count, created_at, updated_at
      `)
      .is('deleted_at', null)
      .order('created_at', { ascending: false })
      .limit(phaseLimit + 1) // +1 to detect "has more"

    if (phaseCursorTs) {
      q = q.lt('created_at', phaseCursorTs)
    }

    // Visibility / user filtering (unchanged behavior).
    if (userId) {
      q = q.eq('user_id', userId)
      if (!(userId === user.id && includeOwnPrivate)) {
        q = q.eq('visibility', 'public')
      }
    } else {
      q = q.eq('visibility', 'public')
    }

    if (courseId) q = q.eq('course_id', courseId)
    if (hashtagPostIds) q = q.in('id', hashtagPostIds)
    if (likedPostIds) q = q.in('id', likedPostIds)

    if (schoolMemberIds) {
      if (phase === 'school') {
        q = q.in('user_id', schoolMemberIds)
      } else {
        // PostgREST `not.in` requires a parenthesized list literal.
        q = q.not('user_id', 'in', `(${schoolMemberIds.join(',')})`)
      }
    }

    return q
  }

  type PostRow = {
    id: string
    user_id: string
    title: string | null
    body: string | null
    visibility: string
    course_id: string | null
    post_kind: string
    likes_count: number
    comments_count: number
    created_at: string
    updated_at: string
  }

  let combined: PostRow[] = []
  let nextCursor: string | null = null

  if (!schoolMemberIds) {
    // Simple single-phase path (no school priority in effect).
    const { data, error } = await buildQuery('other', cursorTs, limit)
    if (error) return errorResponse('Query failed', error.message, 500)
    const rows = (data ?? []) as PostRow[]
    const hasMore = rows.length > limit
    combined = hasMore ? rows.slice(0, limit) : rows
    nextCursor = hasMore ? combined[combined.length - 1].created_at : null
  } else {
    // Phase 1: try to fill from the active phase first.
    const { data: phase1Data, error: phase1Err } = await buildQuery(
      activePhase,
      cursorTs,
      limit,
    )
    if (phase1Err) return errorResponse('Query failed', phase1Err.message, 500)

    const phase1Rows = (phase1Data ?? []) as PostRow[]
    const phase1HasMore = phase1Rows.length > limit
    const phase1Sliced = phase1HasMore ? phase1Rows.slice(0, limit) : phase1Rows

    if (phase1HasMore) {
      // The active phase has more results — stay in this phase.
      combined = phase1Sliced
      const lastTs = combined[combined.length - 1].created_at
      nextCursor = `${activePhase}:${lastTs}`
    } else if (activePhase === 'school') {
      // School phase exhausted — top up from "other" phase to fill the page.
      const remaining = limit - phase1Sliced.length
      if (remaining <= 0) {
        // Page exactly filled by school posts; next page starts the "other"
        // phase from the very top (no timestamp = no `lt` filter).
        combined = phase1Sliced
        nextCursor = 'other:'
      } else {
        const { data: phase2Data, error: phase2Err } = await buildQuery(
          'other',
          null,
          remaining,
        )
        if (phase2Err) return errorResponse('Query failed', phase2Err.message, 500)
        const phase2Rows = (phase2Data ?? []) as PostRow[]
        const phase2HasMore = phase2Rows.length > remaining
        const phase2Sliced = phase2HasMore ? phase2Rows.slice(0, remaining) : phase2Rows

        combined = [...phase1Sliced, ...phase2Sliced]
        if (phase2Sliced.length > 0 && phase2HasMore) {
          nextCursor = `other:${phase2Sliced[phase2Sliced.length - 1].created_at}`
        } else {
          nextCursor = null
        }
      }
    } else {
      // We were in the "other" phase and ran out — end of feed.
      combined = phase1Sliced
      nextCursor = null
    }
  }

  if (combined.length === 0) {
    return json({ posts: [], next_cursor: nextCursor })
  }

  const postIds = combined.map(p => p.id)

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

  const { data: attRows } = await supabase
    .from('post_attachments')
    .select('post_id, note_id, note:notes(title, metadata)')
    .in('post_id', postIds)

  const attachmentsByPost: Record<
    string,
    { note_id: string; title: string; has_pdf: boolean; pdf_filename: string | null }[]
  > = {}
  for (const row of attRows ?? []) {
    const note = row.note as unknown as {
      title: string
      metadata: Record<string, unknown> | null
    } | null
    const meta = note?.metadata
    if (!attachmentsByPost[row.post_id]) attachmentsByPost[row.post_id] = []
    attachmentsByPost[row.post_id].push({
      note_id: row.note_id,
      title: note?.title ?? 'Untitled',
      has_pdf: !!(meta?.pdf_path),
      pdf_filename: (meta?.pdf_filename as string) ?? null,
    })
  }

  const { data: userLikes } = await supabase
    .from('post_likes')
    .select('post_id')
    .eq('user_id', user.id)
    .in('post_id', postIds)

  const likedSet = new Set((userLikes ?? []).map(l => l.post_id))

  // Authors — fetched via the public `user_profiles` view because the
  // base `users` table has a strict per-user RLS policy that would
  // strip joins for any author who isn't the caller.
  const authorIds = Array.from(new Set(combined.map(p => p.user_id)))
  const authorById = new Map<string, {
    id: string
    name: string
    avatar_url: string | null
    school: string | null
    major: string | null
  }>()
  if (authorIds.length > 0) {
    const { data: profiles } = await supabase
      .from('user_profiles')
      .select('id, name, avatar_url, school_affiliation, major')
      .in('id', authorIds)
    for (const row of profiles ?? []) {
      authorById.set(row.id as string, {
        id: row.id as string,
        name: displayName(row.name as string | null, null),
        avatar_url: (row.avatar_url as string | null) ?? null,
        school: nullIfBlank(row.school_affiliation as string | null),
        major: nullIfBlank(row.major as string | null),
      })
    }
  }

  // Batch-fetch image/video media attachments.
  const { data: mediaRows } = await supabase
    .from('post_media')
    .select('post_id, kind, storage_path')
    .in('post_id', postIds)

  const mediaByPost: Record<string, { kind: string; url: string }[]> = {}
  for (const row of mediaRows ?? []) {
    const { data: pub } = supabase.storage.from('post-media').getPublicUrl(row.storage_path as string)
    if (!mediaByPost[row.post_id as string]) mediaByPost[row.post_id as string] = []
    mediaByPost[row.post_id as string].push({
      kind: row.kind as string,
      url: pub.publicUrl,
    })
  }

  const responsePosts = combined.map(p => {
    const author = authorById.get(p.user_id)
      ?? { id: p.user_id, name: 'Student', avatar_url: null, school: null, major: null }
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
