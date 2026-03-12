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
  const schoolId = url.searchParams.get('school_id')?.trim()

  if (!schoolId) {
    return errorResponse('Bad request', 'school_id query parameter is required', 400)
  }

  const page = Math.max(1, Number(url.searchParams.get('page') ?? 1))
  const pageSize = Math.min(100, Math.max(1, Number(url.searchParams.get('pageSize') ?? 20)))
  const search = url.searchParams.get('search')?.trim()

  const { data: school, error: schoolError } = await supabase
    .from('schools')
    .select('id, name')
    .eq('id', schoolId)
    .maybeSingle()

  if (schoolError) {
    return errorResponse('Query failed', schoolError.message, 500)
  }
  if (!school) {
    return errorResponse('Not found', 'School not found', 404)
  }

  // Get course IDs from the junction table, then fetch full course rows
  let courseIdsQuery = supabase
    .from('school_courses')
    .select('course_id', { count: 'exact' })
    .eq('school_id', schoolId)

  const { data: junctionRows, count: totalUnfiltered, error: junctionError } = await courseIdsQuery

  if (junctionError) {
    return errorResponse('Query failed', junctionError.message, 500)
  }

  const allCourseIds = (junctionRows ?? []).map((r: { course_id: string }) => r.course_id)

  if (allCourseIds.length === 0) {
    return json({
      school,
      data: [],
      pagination: { page, pageSize, total: 0, totalPages: 0, hasMore: false },
    })
  }

  let query = supabase
    .from('courses')
    .select('*', { count: 'exact' })
    .in('id', allCourseIds)

  if (search) {
    query = query.or(`name.ilike.%${search}%,code.ilike.%${search}%`)
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
    school,
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
