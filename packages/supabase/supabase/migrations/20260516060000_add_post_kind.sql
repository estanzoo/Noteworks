-- Channel categorization on posts. Mirrors the "Post to" segmented
-- control in the New Post composer (noteworks-library.jsx L7956-7962):
--   note             — sharing a study note
--   study_questions  — asking the community a question
--   discussions      — open-ended discussion (default; matches the
--                      mock's pre-selected pill)
--
-- Stored as TEXT + CHECK so future kinds can be added without an
-- ALTER TYPE / pg_enum dance.
ALTER TABLE public.posts
    ADD COLUMN IF NOT EXISTS post_kind TEXT NOT NULL DEFAULT 'discussions';

ALTER TABLE public.posts
    DROP CONSTRAINT IF EXISTS posts_post_kind_check;

ALTER TABLE public.posts
    ADD CONSTRAINT posts_post_kind_check
    CHECK (post_kind IN ('note', 'study_questions', 'discussions'));

CREATE INDEX IF NOT EXISTS posts_post_kind_created_at_idx
    ON public.posts (post_kind, created_at DESC);
