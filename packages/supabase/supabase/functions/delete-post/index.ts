import { requireAuth } from '../_shared/auth.ts'
import { corsResponse, json, errorResponse } from '../_shared/cors.ts'

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return corsResponse()
  if (req.method !== 'DELETE') {
    return errorResponse('Method not allowed', 'Use DELETE', 405)
  }

  const auth = await requireAuth(req)
  if (auth instanceof Response) return auth
  const { supabase, user } = auth

  const url = new URL(req.url)
  const postId = url.searchParams.get('post_id')
  if (!postId) {
    return errorResponse('Validation failed', 'Query param post_id is required', 400)
  }

  const { data: post, error: fetchErr } = await supabase
    .from('posts')
    .select('id, user_id, deleted_at')
    .eq('id', postId)
    .maybeSingle()

  if (fetchErr) return errorResponse('Query failed', fetchErr.message, 500)
  if (!post) return errorResponse('Not found', 'Post not found', 404)
  if (post.deleted_at) return errorResponse('Not found', 'Post has already been deleted', 404)
  if (post.user_id !== user.id) return errorResponse('Forbidden', 'You can only delete your own posts', 403)

  // Soft delete
  const { error: updateErr } = await supabase
    .from('posts')
    .update({ deleted_at: new Date().toISOString() })
    .eq('id', postId)

  if (updateErr) return errorResponse('Delete failed', updateErr.message, 500)

  return json({ message: 'Post deleted', post_id: postId })
})
