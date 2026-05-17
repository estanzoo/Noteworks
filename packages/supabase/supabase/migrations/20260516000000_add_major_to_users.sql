-- Capture the user's major / program of study, separate from the
-- `course_codes` array (which is used as a free-form interests list today).
ALTER TABLE public.users
    ADD COLUMN IF NOT EXISTS major TEXT;
