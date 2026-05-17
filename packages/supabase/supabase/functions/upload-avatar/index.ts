import { requireAuth } from '../_shared/auth.ts'
import { corsResponse, json, errorResponse } from '../_shared/cors.ts'

// Keep this in sync with the bucket's `file_size_limit` set in
// 20260516040000_create_avatars_bucket.sql.
const MAX_AVATAR_BYTES = 5_242_880 // 5 MB

const ALLOWED_MIMES = new Set([
  'image/jpeg',
  'image/png',
  'image/webp',
  'image/heic',
  'image/heif',
])

// Picks a stable file extension for the storage object so a previous
// upload of a different format gets overwritten cleanly. (We append a
// short cache-busting query to the public URL on the client instead of
// renaming the file every time.)
function extensionForMime(mime: string): string {
  switch (mime) {
    case 'image/png':  return 'png'
    case 'image/webp': return 'webp'
    case 'image/heic': return 'heic'
    case 'image/heif': return 'heif'
    case 'image/jpeg':
    default:           return 'jpg'
  }
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return corsResponse()
  if (req.method !== 'POST') {
    return errorResponse('Method not allowed', 'Use POST', 405)
  }

  const auth = await requireAuth(req)
  if (auth instanceof Response) return auth
  const { supabase, user } = auth

  const contentType = (req.headers.get('content-type') ?? '').toLowerCase()
  if (!ALLOWED_MIMES.has(contentType)) {
    return errorResponse(
      'Validation failed',
      `Content-Type must be one of: ${[...ALLOWED_MIMES].join(', ')}`,
      400,
    )
  }

  const bytes = await req.arrayBuffer()
  if (bytes.byteLength === 0) {
    return errorResponse('Validation failed', 'Request body is empty — attach an image', 400)
  }
  if (bytes.byteLength > MAX_AVATAR_BYTES) {
    return errorResponse(
      'Validation failed',
      `Image exceeds ${MAX_AVATAR_BYTES / 1_048_576} MB limit`,
      400,
    )
  }

  const ext = extensionForMime(contentType)
  const storagePath = `${user.id}/avatar.${ext}`

  const { error: uploadErr } = await supabase.storage
    .from('avatars')
    .upload(storagePath, bytes, {
      contentType,
      // Re-uploads should replace, not 409.
      upsert: true,
      // Tell browsers/iOS to refetch — we bust the URL with a timestamp
      // query on the client below.
      cacheControl: '3600',
    })

  if (uploadErr) return errorResponse('Upload failed', uploadErr.message, 500)

  const { data: publicData } = supabase.storage.from('avatars').getPublicUrl(storagePath)
  // Append a cache-busting timestamp so the new image shows up immediately
  // on every client (Supabase CDN caches the bytes by URL).
  const bustedUrl = `${publicData.publicUrl}?v=${Date.now()}`

  const { error: updateErr } = await supabase
    .from('users')
    .update({ avatar_url: bustedUrl, updated_at: new Date().toISOString() })
    .eq('id', user.id)

  if (updateErr) {
    // Roll back the upload so the user can retry from a clean state.
    await supabase.storage.from('avatars').remove([storagePath])
    return errorResponse('Profile update failed', updateErr.message, 500)
  }

  return json({ avatar_url: bustedUrl }, 200)
})
