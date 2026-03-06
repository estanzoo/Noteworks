import { createClient, SupabaseClient, User } from 'https://esm.sh/@supabase/supabase-js@2'
import { errorResponse } from './cors.ts'

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

  const url = Deno.env.get('SUPABASE_URL')
  const anonKey = Deno.env.get('SUPABASE_ANON_KEY')
  if (!url || !anonKey) {
    return errorResponse('Server error', 'Server configuration error', 500)
  }

  const supabase = createClient(url, anonKey, {
    global: { headers: { Authorization: authHeader } },
  })

  const { data: { user }, error } = await supabase.auth.getUser()
  if (error || !user) {
    return errorResponse('Unauthorized', 'Invalid or expired token', 401)
  }

  return { supabase, user }
}
