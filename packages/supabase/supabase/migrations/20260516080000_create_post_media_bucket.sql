-- Public storage bucket for the image (and later video) files that get
-- attached to community posts via the "Photo / Video" button in the
-- New Post composer. Public read mirrors the avatars bucket so the
-- iOS / web feed can render the URLs directly via AsyncImage.

INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
    'post-media',
    'post-media',
    true,
    20 * 1024 * 1024, -- 20 MB
    ARRAY[
        'image/jpeg',
        'image/png',
        'image/webp',
        'image/heic',
        'image/heif',
        'image/gif'
    ]
)
ON CONFLICT (id) DO UPDATE SET
    public = EXCLUDED.public,
    file_size_limit = EXCLUDED.file_size_limit,
    allowed_mime_types = EXCLUDED.allowed_mime_types;

-- Owner-only writes (storage path is namespaced as `<user_id>/<filename>`).
DROP POLICY IF EXISTS "Owner can upload post media" ON storage.objects;
CREATE POLICY "Owner can upload post media"
    ON storage.objects FOR INSERT
    TO authenticated
    WITH CHECK (
        bucket_id = 'post-media'
        AND auth.uid()::text = (storage.foldername(name))[1]
    );

DROP POLICY IF EXISTS "Owner can update post media" ON storage.objects;
CREATE POLICY "Owner can update post media"
    ON storage.objects FOR UPDATE
    TO authenticated
    USING (
        bucket_id = 'post-media'
        AND auth.uid()::text = (storage.foldername(name))[1]
    )
    WITH CHECK (
        bucket_id = 'post-media'
        AND auth.uid()::text = (storage.foldername(name))[1]
    );

DROP POLICY IF EXISTS "Owner can delete post media" ON storage.objects;
CREATE POLICY "Owner can delete post media"
    ON storage.objects FOR DELETE
    TO authenticated
    USING (
        bucket_id = 'post-media'
        AND auth.uid()::text = (storage.foldername(name))[1]
    );

-- Anyone can read; the post-level RLS on post_media handles privacy.
DROP POLICY IF EXISTS "Post media is publicly readable" ON storage.objects;
CREATE POLICY "Post media is publicly readable"
    ON storage.objects FOR SELECT
    TO anon, authenticated
    USING (bucket_id = 'post-media');
