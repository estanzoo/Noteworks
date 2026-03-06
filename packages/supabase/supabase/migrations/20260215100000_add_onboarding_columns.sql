-- Add onboarding columns to public.users
ALTER TABLE public.users
  ADD COLUMN IF NOT EXISTS year_of_study TEXT,
  ADD COLUMN IF NOT EXISTS school_affiliation TEXT,
  ADD COLUMN IF NOT EXISTS school_email TEXT,
  ADD COLUMN IF NOT EXISTS onboarding_completed_at TIMESTAMPTZ;
