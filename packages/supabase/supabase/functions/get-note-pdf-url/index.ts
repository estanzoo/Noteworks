// Signed URL minter for note PDFs. The caller is authenticated, and the
// note SELECT goes through the user-scoped client so RLS decides whether
// they can see this note (owner / course-enrolled / attached to a
// community post they can see — covered by the policies in
// `20260203100003_enable_rls_rest.sql` +
// `20260515000000_temp_allow_courseless_note_uploads.sql`).
//
// Once that access check has passed, we mint the signed URL with the
// service-role client. The storage bucket `notes-pdfs` only has an
// owner-only SELECT policy (migration 20260215120000), so without this
// the storage layer denies `createSignedUrl` for non-owners and the
// function would return a confusing 500 ("Storage error") to anyone
// reading a community-shared PDF. The DB-level access check above is
// the source of truth; the admin client is purely there to bypass the
// narrower storage RLS.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.39.0'
import { requireAuth } from '../_shared/auth.ts'
import { corsResponse, json, errorResponse } from '../_shared/cors.ts'

const DEFAULT_EXPIRY_SECONDS = 3600 // 1 hour

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return corsResponse()
  if (req.method !== 'GET') {
    return errorResponse('Method not allowed', 'Use GET', 405)
  }

  const auth = await requireAuth(req)
  if (auth instanceof Response) return auth
  const { supabase } = auth

  const url = new URL(req.url)
  const noteId = url.searchParams.get('note_id')
  const expiresIn = Math.min(
    86400,
    Math.max(60, Number(url.searchParams.get('expires_in') ?? DEFAULT_EXPIRY_SECONDS)),
  )

  if (!noteId) {
    return errorResponse('Validation failed', 'Query param note_id is required', 400)
  }

  // Access check: the user-scoped client + RLS decides whether this
  // caller is allowed to see the note at all (owner, enrolled, or it's
  // attached to a community post they can read).
  const { data: note, error: noteErr } = await supabase
    .from('notes')
    .select('id, metadata')
    .eq('id', noteId)
    .maybeSingle()

  if (noteErr) return errorResponse('Query failed', noteErr.message, 500)
  if (!note) return errorResponse('Not found', 'Note not found', 404)

  const metadata = note.metadata as Record<string, unknown> | null
  if (!metadata?.pdf_path || typeof metadata.pdf_path !== 'string') {
    return errorResponse('Not found', 'This note has no PDF attached', 404)
  }

  // Mint the signed URL with the service-role client so we don't get
  // bounced by the narrower owner-only SELECT policy on the
  // `notes-pdfs` storage bucket. Access has already been gated above.
  const supabaseUrl = Deno.env.get('SUPABASE_URL')!
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
  const admin = createClient(supabaseUrl, serviceKey)

  const { data: signed, error: signErr } = await admin.storage
    .from('notes-pdfs')
    .createSignedUrl(metadata.pdf_path, expiresIn)

  if (signErr || !signed?.signedUrl) {
    return errorResponse('Storage error', signErr?.message ?? 'Could not generate signed URL', 500)
  }

  return json({
    note_id: noteId,
    pdf_filename: metadata.pdf_filename ?? null,
    signed_url: signed.signedUrl,
    expires_in: expiresIn,
  })
})
