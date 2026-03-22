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
  const commentId = url.searchParams.get('comment_id')
  if (!commentId) {
    return errorResponse('Validation failed', 'Query param comment_id is required', 400)
  }

  const { data: comment, error: fetchErr } = await supabase
    .from('comments')
    .select('id, user_id')
    .eq('id', commentId)
    .maybeSingle()

  if (fetchErr) return errorResponse('Query failed', fetchErr.message, 500)
  if (!comment) return errorResponse('Not found', 'Comment not found', 404)
  if (comment.user_id !== user.id) {
    return errorResponse('Forbidden', 'You can only delete your own comments', 403)
  }

  // Hard delete — cascades to child replies via FK ON DELETE CASCADE
  const { error: deleteErr } = await supabase
    .from('comments')
    .delete()
    .eq('id', commentId)

  if (deleteErr) return errorResponse('Delete failed', deleteErr.message, 500)

  return json({ message: 'Comment deleted', comment_id: commentId })
})
