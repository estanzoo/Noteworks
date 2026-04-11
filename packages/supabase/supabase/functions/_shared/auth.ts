import { createClient, SupabaseClient, User } from 'https://esm.sh/@supabase/supabase-js@2'
import { errorResponse } from './cors.ts'

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')
const SUPABASE_ANON_KEY = Deno.env.get('SUPABASE_ANON_KEY')
if (!SUPABASE_URL || !SUPABASE_ANON_KEY) {
  throw new Error('Missing SUPABASE_URL or SUPABASE_ANON_KEY environment variables')
}

export interface AuthContext {
  supabase: SupabaseClient
  user: User
}

/**
 * Extracts Bearer token, creates a Supabase client scoped to the caller,
 * and returns the authenticated user. Returns an error Response on failure.
 */
export async function requireAuth(req: Request): Promise<AuthContext | Response> {
  const authHeader = req.headers.get('Authorization')
  if (!authHeader?.startsWith('Bearer ')) {
    return errorResponse('Unauthorized', 'Missing or invalid Authorization header', 401)
  }

  const token = authHeader.replace('Bearer ', '')

  const supabase = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
    global: { headers: { Authorization: authHeader } },
  })

  const { data: { user }, error } = await supabase.auth.getUser(token)
  if (error || !user) {
    return errorResponse('Unauthorized', 'Invalid or expired token', 401)
  }

  return { supabase, user }
}
