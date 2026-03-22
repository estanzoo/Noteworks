import { requireAuth } from '../_shared/auth.ts'
import { corsResponse, json, errorResponse } from '../_shared/cors.ts'

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return corsResponse()
  if (req.method !== 'GET') {
    return errorResponse('Method not allowed', 'Use GET', 405)
  }

  const auth = await requireAuth(req)
  if (auth instanceof Response) return auth
  const { supabase } = auth

  const url = new URL(req.url)
  const q = url.searchParams.get('q')?.toLowerCase().trim() ?? ''
  const limit = Math.min(20, Math.max(1, Number(url.searchParams.get('limit') ?? 10)))

  if (!q) {
    return errorResponse('Validation failed', 'Query param q is required', 400)
  }

  // Prefix search using ilike
  const { data: hashtags, error } = await supabase
    .from('hashtags')
    .select('id, name, post_count')
    .ilike('name', `${q}%`)
    .order('post_count', { ascending: false })
    .limit(limit)

  if (error) return errorResponse('Query failed', error.message, 500)

  return json({ hashtags: hashtags ?? [] })
})
