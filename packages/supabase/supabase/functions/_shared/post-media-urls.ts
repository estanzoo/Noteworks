import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.39.0'

const SIGNED_URL_TTL_SEC = 60 * 60 * 24 // 24 hours

type MediaRow = { kind: string; storage_path: string }

/**
 * Turn `post_media.storage_path` rows into client-loadable URLs.
 * Prefer signed URLs (same idea as `get-note-pdf-url`) so images work
 * even when the bucket isn't configured for anonymous public reads.
 */
export async function resolvePostMediaUrls(
  rows: MediaRow[],
): Promise<{ kind: string; url: string }[]> {
  if (rows.length === 0) return []

  const supabaseUrl = Deno.env.get('SUPABASE_URL')
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')
  if (!supabaseUrl || !serviceKey) {
    throw new Error('Missing SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY')
  }

  const admin = createClient(supabaseUrl, serviceKey)
  const out: { kind: string; url: string }[] = []

  for (const row of rows) {
    const path = row.storage_path?.trim()
    if (!path) continue

    const { data: signed, error: signErr } = await admin.storage
      .from('post-media')
      .createSignedUrl(path, SIGNED_URL_TTL_SEC)

    if (!signErr && signed?.signedUrl) {
      out.push({ kind: row.kind, url: signed.signedUrl })
      continue
    }

    const { data: pub } = admin.storage.from('post-media').getPublicUrl(path)
    out.push({ kind: row.kind, url: pub.publicUrl })
  }

  return out
}
