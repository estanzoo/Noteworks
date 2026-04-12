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
  const page = Math.max(1, Number(url.searchParams.get('page') ?? 1))
  const pageSize = Math.min(100, Math.max(1, Number(url.searchParams.get('pageSize') ?? 20)))
  const search = url.searchParams.get('search')?.trim()
  const country = url.searchParams.get('country')?.trim().toUpperCase()

  let query = supabase
    .from('schools')
    .select('*', { count: 'exact' })

  if (search) {
    query = query.or(`name.ilike.%${search}%,location.ilike.%${search}%`)
  }
  if (country) {
    query = query.eq('country', country)
  }

  const from = (page - 1) * pageSize
  const { data, count, error } = await query
    .order('name')
    .range(from, from + pageSize - 1)

  if (error) {
    return errorResponse('Query failed', error.message, 500)
  }

  const total = count ?? 0
  return json({
    data,
    pagination: {
      page,
      pageSize,
      total,
      totalPages: Math.ceil(total / pageSize),
      hasMore: from + pageSize < total,
    },
  })
})
