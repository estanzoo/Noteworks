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
  const noteId = url.searchParams.get('id')

  // Single note by ID
  if (noteId) {
    const { data, error } = await supabase
      .from('notes')
      .select('*, courses(id, name, code)')
      .eq('id', noteId)
      .maybeSingle()

    if (error) return errorResponse('Query failed', error.message, 500)
    if (!data) return errorResponse('Not found', 'Note not found', 404)
    return json(data)
  }

  // List notes with optional filters and pagination
  const courseId = url.searchParams.get('course_id')
  const page = Math.max(1, Number(url.searchParams.get('page') ?? 1))
  const pageSize = Math.min(100, Math.max(1, Number(url.searchParams.get('pageSize') ?? 20)))
  const sortBy = url.searchParams.get('sortBy') ?? 'created_at'
  const sortOrder = url.searchParams.get('sortOrder') === 'asc' ? true : false

  let query = supabase
    .from('notes')
    .select('*, courses(id, name, code)', { count: 'exact' })

  if (courseId) {
    query = query.eq('course_id', courseId)
  }

  const from = (page - 1) * pageSize
  const { data, count, error } = await query
    .order(sortBy, { ascending: sortOrder })
    .range(from, from + pageSize - 1)

  if (error) return errorResponse('Query failed', error.message, 500)

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
