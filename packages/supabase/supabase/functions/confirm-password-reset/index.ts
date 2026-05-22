import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { corsResponse, json, errorResponse } from '../_shared/cors.ts'

const MIN_PASSWORD_LENGTH = 8
const OTP_LENGTH = 6
const EMAIL_REGEX = /^[^\s@]+@[^\s@]+\.[^\s@]+$/

type ValidBody = {
  email: string
  code: string
  password: string
}

function validate(body: unknown): ValidBody | { errors: Record<string, string> } {
  if (body == null || typeof body !== 'object' || Array.isArray(body)) {
    return { errors: { body: 'JSON body with email, code, and password is required' } }
  }

  const o = body as Record<string, unknown>
  const email = typeof o.email === 'string' ? o.email.trim().toLowerCase() : ''
  const codeRaw = typeof o.code === 'string' ? o.code.trim() : ''
  const code = codeRaw.replace(/\D/g, '')
  const password = typeof o.password === 'string' ? o.password : ''
  const confirmPassword = typeof o.confirm_password === 'string' ? o.confirm_password : password

  const errors: Record<string, string> = {}

  if (email.length === 0) errors.email = 'Email is required'
  else if (!EMAIL_REGEX.test(email)) errors.email = 'Invalid email format'

  if (code.length !== OTP_LENGTH) {
    errors.code = `Recovery code must be ${OTP_LENGTH} digits`
  }

  if (password.length < MIN_PASSWORD_LENGTH) {
    errors.password = `Password must be at least ${MIN_PASSWORD_LENGTH} characters`
  }

  if (password !== confirmPassword) {
    errors.confirm_password = 'Passwords do not match'
  }

  if (Object.keys(errors).length > 0) return { errors }

  return { email, code, password }
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return corsResponse()
  if (req.method !== 'POST') {
    return errorResponse('Method not allowed', 'Use POST', 405)
  }

  let body: unknown
  try {
    body = await req.json()
  } catch {
    return errorResponse('Validation failed', 'Invalid JSON body', 400)
  }

  const validated = validate(body)
  if ('errors' in validated) {
    const first = Object.values(validated.errors)[0] ?? 'Invalid request'
    return errorResponse('Validation failed', first, 400, { errors: validated.errors })
  }

  const supabaseUrl = Deno.env.get('SUPABASE_URL')
  const anonKey = Deno.env.get('SUPABASE_ANON_KEY')
  if (!supabaseUrl || !anonKey) {
    return errorResponse('Server misconfigured', 'Missing Supabase environment', 500)
  }

  // Edge runtimes have no persisted auth storage; setSession after verifyOtp
  // is required before updateUser (otherwise GoTrue returns "Auth session missing!").
  const supabase = createClient(supabaseUrl, anonKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  })

  const { data: verifyData, error: verifyErr } = await supabase.auth.verifyOtp({
    email: validated.email,
    token: validated.code,
    type: 'recovery',
  })

  if (verifyErr || !verifyData.session) {
    return errorResponse(
      'Invalid code',
      'Invalid or expired recovery code. Request a new code and try again.',
      400,
    )
  }

  const { error: sessionErr } = await supabase.auth.setSession({
    access_token: verifyData.session.access_token,
    refresh_token: verifyData.session.refresh_token,
  })

  if (sessionErr) {
    return errorResponse('Session error', sessionErr.message, 500)
  }

  const { error: updateErr } = await supabase.auth.updateUser({
    password: validated.password,
  })

  if (updateErr) {
    const msg = updateErr.message.toLowerCase()
    if (msg.includes('weak') || msg.includes('password')) {
      return errorResponse('Validation failed', updateErr.message, 400)
    }
    return errorResponse('Update failed', updateErr.message, 500)
  }

  return json({ message: 'Password updated successfully' })
})
