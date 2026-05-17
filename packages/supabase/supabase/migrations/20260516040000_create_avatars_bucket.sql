-- Public `avatars` bucket for profile photos.
--
-- Avatars need to be visible to every community reader (post / comment
-- author rows), so the bucket is `public = true` and read is open.
-- Writes are scoped to the owning user's folder, mirroring how
-- `notes-pdfs` (20260215120000) restricts uploads.
--
-- Path layout: `{user_id}/avatar.{ext}` (optionally with a cache-busting
-- suffix), so `(storage.foldername(name))[1]` is the user's UUID.

INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
    'avatars',
    'avatars',
    true,
    5_242_880, -- 5 MB
    ARRAY['image/jpeg', 'image/png', 'image/webp', 'image/heic', 'image/heif']
)
ON CONFLICT (id) DO UPDATE SET
    public = EXCLUDED.public,
    file_size_limit = EXCLUDED.file_size_limit,
    allowed_mime_types = EXCLUDED.allowed_mime_types;

-- Owner can upload (insert) to their own folder.
CREATE POLICY "Owner can upload avatar"
    ON storage.objects FOR INSERT TO authenticated
    WITH CHECK (
        bucket_id = 'avatars'
        AND (storage.foldername(name))[1] = auth.uid()::text
    );

-- Owner can overwrite their existing avatar.
CREATE POLICY "Owner can update avatar"
    ON storage.objects FOR UPDATE TO authenticated
    USING (
        bucket_id = 'avatars'
        AND (storage.foldername(name))[1] = auth.uid()::text
    );

-- Owner can delete their own avatar.
CREATE POLICY "Owner can delete avatar"
    ON storage.objects FOR DELETE TO authenticated
    USING (
        bucket_id = 'avatars'
        AND (storage.foldername(name))[1] = auth.uid()::text
    );

-- Avatars are public — anyone (even unauthenticated readers) can fetch
-- them so community avatars render without per-user signed URLs.
CREATE POLICY "Avatars are publicly readable"
    ON storage.objects FOR SELECT TO anon, authenticated
    USING (bucket_id = 'avatars');
