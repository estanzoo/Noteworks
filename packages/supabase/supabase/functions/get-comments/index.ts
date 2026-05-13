import { requireAuth } from '../_shared/auth.ts'
import { corsResponse, json, errorResponse } from '../_shared/cors.ts'

interface CommentRow {
  id: string
  post_id: string
  user_id: string
  parent_comment_id: string | null
  body: string
  likes_count: number
  visibility: string
  created_at: string
  updated_at: string
  author: { id: string; name: string | null } | null
}

interface CommentTree {
  id: string
  post_id: string
  user_id: string
  author: { id: string; name: string | null }
  parent_comment_id: string | null
  body: string
  likes_count: number
  has_liked: boolean
  visibility: string
  created_at: string
  updated_at: string
  replies: CommentTree[]
}

function buildTree(comments: CommentRow[], likedSet: Set<string>): CommentTree[] {
  const map = new Map<string, CommentTree>()
  const roots: CommentTree[] = []

  for (const c of comments) {
    const author = c.author as unknown as { id: string; name: string | null } | null
    map.set(c.id, {
      id: c.id,
      post_id: c.post_id,
      user_id: c.user_id,
      author: author ?? { id: c.user_id, name: null },
      parent_comment_id: c.parent_comment_id,
      body: c.body,
      likes_count: c.likes_count,
      has_liked: likedSet.has(c.id),
      visibility: c.visibility,
      created_at: c.created_at,
      updated_at: c.updated_at,
      replies: [],
    })
  }

  for (const c of comments) {
    const node = map.get(c.id)!
    if (c.parent_comment_id && map.has(c.parent_comment_id)) {
      map.get(c.parent_comment_id)!.replies.push(node)
    } else {
      roots.push(node)
    }
  }

  return roots
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
  const postId = url.searchParams.get('post_id')
  if (!postId) {
    return errorResponse('Validation failed', 'Query param post_id is required', 400)
  }

  const cursor = url.searchParams.get('cursor')
  const limit = Math.min(100, Math.max(1, Number(url.searchParams.get('limit') ?? 50)))

  // Fetch all comments for this post (including nested).
  // We fetch top-level with pagination, then eagerly load all their descendants.
  let topQuery = supabase
    .from('comments')
    .select(`
      id, post_id, user_id, parent_comment_id, body,
      likes_count, visibility, created_at, updated_at,
      author:users!comments_user_id_fkey(id, name)
    `)
    .eq('post_id', postId)
    .is('parent_comment_id', null)
    .order('created_at', { ascending: true })
    .limit(limit + 1)

  if (cursor) {
    topQuery = topQuery.gt('created_at', cursor)
  }

  const { data: topComments, error: topErr } = await topQuery

  if (topErr) return errorResponse('Query failed', topErr.message, 500)
  if (!topComments || topComments.length === 0) {
    return json({ data: [], next_cursor: null })
  }

  const hasMore = topComments.length > limit
  const sliced = hasMore ? topComments.slice(0, limit) : topComments
  const nextCursor = hasMore ? sliced[sliced.length - 1].created_at : null

  const topIds = sliced.map(c => c.id)

  // Fetch all replies that descend from these top-level comments.
  // We use a recursive approach: fetch children, then children of children, etc.
  const allComments = [...sliced] as CommentRow[]
  let parentIds = topIds

  while (parentIds.length > 0) {
    const { data: children } = await supabase
      .from('comments')
      .select(`
        id, post_id, user_id, parent_comment_id, body,
        likes_count, visibility, created_at, updated_at,
        author:users!comments_user_id_fkey(id, name)
      `)
      .eq('post_id', postId)
      .in('parent_comment_id', parentIds)
      .order('created_at', { ascending: true })

    if (!children || children.length === 0) break
    allComments.push(...(children as CommentRow[]))
    parentIds = children.map(c => c.id)
  }

  // Batch-check which of these comments the current user has liked
  const commentIds = allComments.map(c => c.id)
  const likedSet = new Set<string>()
  if (commentIds.length > 0) {
    const { data: userLikes } = await supabase
      .from('comment_likes')
      .select('comment_id')
      .eq('user_id', user.id)
      .in('comment_id', commentIds)

    for (const row of userLikes ?? []) likedSet.add(row.comment_id)
  }

  const tree = buildTree(allComments, likedSet)

  return json({ data: tree, next_cursor: nextCursor })
})
