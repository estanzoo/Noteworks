-- Rename `public.feedback` columns to match Profile → Feedback labels
-- (FeedbackSection.swift). Quoted identifiers keep spaces/punctuation.

ALTER TABLE public.feedback RENAME COLUMN feedback_type TO "Type";
ALTER TABLE public.feedback RENAME COLUMN area TO "Where did it happen?";
ALTER TABLE public.feedback RENAME COLUMN area_other TO "Where exactly?";
ALTER TABLE public.feedback RENAME COLUMN priority TO "Impact";
ALTER TABLE public.feedback RENAME COLUMN title TO "Short Summary";
ALTER TABLE public.feedback RENAME COLUMN body TO "What happened?";
ALTER TABLE public.feedback RENAME COLUMN media_paths TO "Photos";

ALTER TABLE public.feedback DROP CONSTRAINT IF EXISTS feedback_title_len;
ALTER TABLE public.feedback DROP CONSTRAINT IF EXISTS feedback_body_len;

ALTER TABLE public.feedback
  ADD CONSTRAINT feedback_short_summary_len
    CHECK (char_length("Short Summary") BETWEEN 1 AND 200),
  ADD CONSTRAINT feedback_what_happened_len
    CHECK (char_length("What happened?") BETWEEN 1 AND 5000);
