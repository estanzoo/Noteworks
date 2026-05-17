// Single-file image uploader for the New Post composer's
// "Photo / Video" button. The client uploads each picked image to
// this endpoint *before* calling create-post, then passes back the
// returned `storage_path` in `create-post`'s `media_paths[]`. That
// two-step flow mirrors the existing PDF pipeline
// (upload-note-pdf -> create-post with attachment_note_ids[]) so
// half-completed posts don't leave orphaned rows in `post_media`.
//
// Storage layout: `post-media/<user_id>/<uuid>.<ext>` — matches the
// avatars bucket convention so the storage RLS policy
// (`auth.uid()::text = (storage.foldername(name))[1]`) accepts the
// write.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.39.0'
import { requireAuth } from '../_shared/auth.ts'
import { corsResponse, json, errorResponse } from '../_shared/cors.ts'

const MAX_BYTES = 20 * 1024 * 1024 // 20 MB — matches the bucket limit.

const ALLOWED_MIMES = new Set([
  'image/jpeg',
  'image/png',
  'image/webp',
  'image/heic',
  'image/heif',
  'image/gif',
])

function extensionForMime(mime: string): string {
  switch (mime) {
    case 'image/jpeg': return 'jpg'
    case 'image/png':  return 'png'
    case 'image/webp': return 'webp'
    case 'image/heic': return 'heic'
    case 'image/heif': return 'heif'
    case 'image/gif':  return 'gif'
    default:           return 'bin'
  }
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return corsResponse()
  if (req.method !== 'POST') {
    return errorResponse('Method not allowed', 'Use POST', 405)
  }

  const auth = await requireAuth(req)
  if (auth instanceof Response) return auth
  const { user } = auth

  const contentType = (req.headers.get('content-type') ?? '').toLowerCase()
  if (!ALLOWED_MIMES.has(contentType)) {
    return errorResponse(
      'Validation failed',
      'Content-Type must be one of: ' + Array.from(ALLOWED_MIMES).join(', '),
      400,
    )
  }

  const bytes = new Uint8Array(await req.arrayBuffer())
  if (bytes.byteLength === 0) {
    return errorResponse('Validation failed', 'Empty body', 400)
  }
  if (bytes.byteLength > MAX_BYTES) {
    return errorResponse('Validation failed', `Image must be at most ${MAX_BYTES} bytes`, 400)
  }

  // Service-role client so the upload bypasses the per-row RLS check on
  // `post_media` (we only insert there once `create-post` succeeds).
  const supabaseUrl = Deno.env.get('SUPABASE_URL')!
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
  const admin = createClient(supabaseUrl, serviceKey)

  const ext = extensionForMime(contentType)
  const storagePath = `${user.id}/${crypto.randomUUID()}.${ext}`

  const { error: uploadErr } = await admin.storage
    .from('post-media')
    .upload(storagePath, bytes, {
      contentType,
      upsert: false,
      cacheControl: '3600',
    })

  if (uploadErr) {
    return errorResponse('Upload failed', uploadErr.message, 500)
  }

  const { data: publicData } = admin.storage.from('post-media').getPublicUrl(storagePath)

  return json(
    {
      storage_path: storagePath,
      url: publicData.publicUrl,
      content_type: contentType,
      file_size: bytes.byteLength,
    },
    200,
  )
})
