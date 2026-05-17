-- Image / video attachments on community posts. PDFs continue to flow
-- through `notes` + `post_attachments` (so the NoteEditor can still
-- preview them); media files live here so they get their own bucket
-- and don't pollute the user's library.

CREATE TABLE IF NOT EXISTS public.post_media (
    id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    post_id      UUID NOT NULL REFERENCES public.posts(id) ON DELETE CASCADE,
    user_id      UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    kind         TEXT NOT NULL,
    storage_path TEXT NOT NULL,
    content_type TEXT,
    file_size    INTEGER,
    width        INTEGER,
    height       INTEGER,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),

    CONSTRAINT post_media_kind_check CHECK (kind IN ('image', 'video'))
);

CREATE INDEX IF NOT EXISTS post_media_post_id_idx ON public.post_media (post_id);
CREATE INDEX IF NOT EXISTS post_media_user_id_idx ON public.post_media (user_id);

ALTER TABLE public.post_media ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Post media is readable when the post is" ON public.post_media;
CREATE POLICY "Post media is readable when the post is"
    ON public.post_media FOR SELECT
    TO anon, authenticated
    USING (
        EXISTS (
            SELECT 1 FROM public.posts p
            WHERE p.id = post_id
              AND p.deleted_at IS NULL
              AND (p.visibility = 'public' OR p.user_id = auth.uid())
        )
    );

DROP POLICY IF EXISTS "Author can insert their own post media" ON public.post_media;
CREATE POLICY "Author can insert their own post media"
    ON public.post_media FOR INSERT
    TO authenticated
    WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "Author can delete their own post media" ON public.post_media;
CREATE POLICY "Author can delete their own post media"
    ON public.post_media FOR DELETE
    TO authenticated
    USING (auth.uid() = user_id);
