import { requireAuth } from '../_shared/auth.ts'
import { corsResponse, json, errorResponse } from '../_shared/cors.ts'

const MAX_BODY = 5_000

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
  const commentBody = typeof body.body === 'string' ? body.body.trim() : ''
  const parentCommentId = typeof body.parent_comment_id === 'string' ? body.parent_comment_id.trim() : null

  const errors: Record<string, string> = {}
  if (!postId) errors.post_id = 'post_id is required'
  if (!commentBody) errors.body = 'Comment body is required'
  else if (commentBody.length > MAX_BODY) errors.body = `Body must be at most ${MAX_BODY} characters`

  if (Object.keys(errors).length > 0) {
    return errorResponse('Validation failed', 'Invalid input', 400, errors)
  }

  // Verify post exists and is not deleted
  const { data: post, error: postErr } = await supabase
    .from('posts')
    .select('id, deleted_at')
    .eq('id', postId)
    .maybeSingle()

  if (postErr) return errorResponse('Query failed', postErr.message, 500)
  if (!post) return errorResponse('Not found', 'Post not found', 404)
  if (post.deleted_at) return errorResponse('Not found', 'Post has been deleted', 404)

  // Verify parent comment if provided
  if (parentCommentId) {
    const { data: parent, error: parentErr } = await supabase
      .from('comments')
      .select('id, post_id')
      .eq('id', parentCommentId)
      .maybeSingle()

    if (parentErr) return errorResponse('Query failed', parentErr.message, 500)
    if (!parent) return errorResponse('Not found', 'Parent comment not found', 404)
    if (parent.post_id !== postId) {
      return errorResponse('Validation failed', 'Parent comment does not belong to this post', 400)
    }
  }

  const { data: comment, error: insertErr } = await supabase
    .from('comments')
    .insert({
      post_id: postId,
      user_id: user.id,
      parent_comment_id: parentCommentId,
      body: commentBody,
    })
    .select(`
      id, post_id, user_id, parent_comment_id, body,
      likes_count, visibility, created_at, updated_at,
      author:users!comments_user_id_fkey(id, name)
    `)
    .single()

  if (insertErr) return errorResponse('Insert failed', insertErr.message, 500)

  const author = comment.author as unknown as { id: string; name: string | null } | null

  return json({
    id: comment.id,
    post_id: comment.post_id,
    user_id: comment.user_id,
    author: author ?? { id: comment.user_id, name: null },
    parent_comment_id: comment.parent_comment_id,
    body: comment.body,
    likes_count: comment.likes_count,
    visibility: comment.visibility,
    created_at: comment.created_at,
    updated_at: comment.updated_at,
    replies: [],
  }, 201)
})
