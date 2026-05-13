import { requireAuth } from '../_shared/auth.ts'
import { corsResponse, json, errorResponse } from '../_shared/cors.ts'

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return corsResponse()
  if (req.method !== 'POST') {
    return errorResponse('Method not allowed', 'Use POST', 405)
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

  const commentId = typeof body.comment_id === 'string' ? body.comment_id.trim() : ''
  if (!commentId) return errorResponse('Validation failed', 'comment_id is required', 400)

  // Verify comment exists and the parent post is not soft-deleted
  const { data: comment, error: commentErr } = await supabase
    .from('comments')
    .select('id, post:posts!comments_post_id_fkey(id, deleted_at)')
    .eq('id', commentId)
    .maybeSingle()

  if (commentErr) return errorResponse('Query failed', commentErr.message, 500)
  if (!comment) return errorResponse('Not found', 'Comment not found', 404)

  const post = comment.post as unknown as { id: string; deleted_at: string | null } | null
  if (!post || post.deleted_at) {
    return errorResponse('Not found', 'Comment not found', 404)
  }

  // Check if already liked
  const { data: existingLike } = await supabase
    .from('comment_likes')
    .select('comment_id')
    .eq('comment_id', commentId)
    .eq('user_id', user.id)
    .maybeSingle()

  let liked: boolean

  if (existingLike) {
    const { error: delErr } = await supabase
      .from('comment_likes')
      .delete()
      .eq('comment_id', commentId)
      .eq('user_id', user.id)
    if (delErr) return errorResponse('Delete failed', delErr.message, 500)
    liked = false
  } else {
    const { error: insErr } = await supabase
      .from('comment_likes')
      .insert({ comment_id: commentId, user_id: user.id })
    if (insErr) return errorResponse('Insert failed', insErr.message, 500)
    liked = true
  }

  // Fetch updated count
  const { data: updated } = await supabase
    .from('comments')
    .select('likes_count')
    .eq('id', commentId)
    .single()

  return json({ liked, likes_count: updated?.likes_count ?? 0 })
})
