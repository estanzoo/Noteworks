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

  const postId = typeof body.post_id === 'string' ? body.post_id.trim() : ''
  if (!postId) return errorResponse('Validation failed', 'post_id is required', 400)

  // Verify post exists and is not deleted
  const { data: post, error: postErr } = await supabase
    .from('posts')
    .select('id, deleted_at')
    .eq('id', postId)
    .maybeSingle()

  if (postErr) return errorResponse('Query failed', postErr.message, 500)
  if (!post) return errorResponse('Not found', 'Post not found', 404)
  if (post.deleted_at) return errorResponse('Not found', 'Post has been deleted', 404)

  // Check if already liked
  const { data: existingLike } = await supabase
    .from('post_likes')
    .select('post_id')
    .eq('post_id', postId)
    .eq('user_id', user.id)
    .maybeSingle()

  let liked: boolean

  if (existingLike) {
    // Unlike
    const { error: delErr } = await supabase
      .from('post_likes')
      .delete()
      .eq('post_id', postId)
      .eq('user_id', user.id)
    if (delErr) return errorResponse('Delete failed', delErr.message, 500)
    liked = false
  } else {
    // Like
    const { error: insErr } = await supabase
      .from('post_likes')
      .insert({ post_id: postId, user_id: user.id })
    if (insErr) return errorResponse('Insert failed', insErr.message, 500)
    liked = true
  }

  // Fetch updated count
  const { data: updated } = await supabase
    .from('posts')
    .select('likes_count')
    .eq('id', postId)
    .single()

  return json({ liked, likes_count: updated?.likes_count ?? 0 })
})
