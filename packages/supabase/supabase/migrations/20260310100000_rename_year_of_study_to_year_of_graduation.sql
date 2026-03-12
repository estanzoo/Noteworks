-- Rename year_of_study to year_of_graduation and change type from TEXT to INTEGER
ALTER TABLE public.users
  ADD COLUMN IF NOT EXISTS year_of_graduation INTEGER;

-- Migrate any existing text values (best-effort: extract trailing year number)
UPDATE public.users
SET year_of_graduation = NULL
WHERE year_of_study IS NOT NULL;

ALTER TABLE public.users
  DROP COLUMN IF EXISTS year_of_study;
