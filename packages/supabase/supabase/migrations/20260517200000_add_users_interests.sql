-- Separate "Field of Interests" from "course codes" on the users table.
--
-- Until now the onboarding "Any Field of Interests?" chips (AI, Soccer,
-- Coding, …) were stuffed into `users.course_codes`, which is meant to
-- hold registrar course identifiers (ECON101, BIO-220, …). That conflation
-- meant every interest tag also ran through the `courses` lookup in
-- `submit-onboarding` (and was simply discarded when no course existed
-- with that "code") — and any downstream consumer of `course_codes`
-- (Profile screen, future course-enrollment surfaces) saw garbage.
--
-- Fix: add a dedicated `interests` text[] column for the chips and
-- migrate the existing rows over so no user loses their picks. We then
-- clear `course_codes` because every value in there today is actually
-- an interest, not a course code, and leaving them in would re-confuse
-- future logic that takes the column at face value.

ALTER TABLE public.users
    ADD COLUMN IF NOT EXISTS interests TEXT[] DEFAULT '{}';

-- Backfill: copy any existing values from `course_codes` into `interests`
-- (only when `interests` is still its default empty array, so re-running
-- the migration won't clobber a fresh onboarding submission).
UPDATE public.users
SET interests = course_codes
WHERE COALESCE(array_length(interests, 1), 0) = 0
  AND COALESCE(array_length(course_codes, 1), 0) > 0;

-- Reset `course_codes` to the empty default. Real course identifiers
-- will be repopulated when we ship a registrar-grade course picker.
UPDATE public.users
SET course_codes = '{}'
WHERE COALESCE(array_length(course_codes, 1), 0) > 0;
