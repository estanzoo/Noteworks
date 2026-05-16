-- TEMPORARY: allow community PDF uploads without an associated course.
-- Will be tightened back up later once we wire course selection into the
-- community upload flow. Do not rely on this in long-term schema design.

-- 1. Make notes.course_id optional. The FK + ON DELETE CASCADE remain.
ALTER TABLE public.notes
    ALTER COLUMN course_id DROP NOT NULL;

-- 2. Allow anyone who can see a post to read the notes attached to it.
--    Without this, the existing notes SELECT policy (owner / enrolled in
--    notes.course_id) blocks community readers from fetching attached PDFs
--    because course_id may now be NULL or unrelated to the viewer.
CREATE POLICY "Notes attached to visible posts are readable"
    ON public.notes
    FOR SELECT
    TO authenticated
    USING (
        EXISTS (
            SELECT 1
            FROM public.post_attachments pa
            JOIN public.posts p ON p.id = pa.post_id
            WHERE pa.note_id = notes.id
              AND (
                  (p.visibility = 'public' AND p.deleted_at IS NULL)
                  OR p.user_id = auth.uid()
              )
        )
    );
