import { createClient, SupabaseClient, User } from 'https://esm.sh/@supabase/supabase-js@2'
import { errorResponse } from './cors.ts'

const SUPABASE_URL = 'https://canhewvuprjwmpopcloj.supabase.co'
const SUPABASE_ANON_KEY =
  'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImNhbmhld3Z1cHJqd21wb3BjbG9qIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Njk5NjI1NDgsImV4cCI6MjA4NTUzODU0OH0.jp-RcV0gxHHozwgL4pOlNkwUsjUbzoZTJ6MRJH4Oo8Y'

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
