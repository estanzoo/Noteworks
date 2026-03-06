-- Add credits column to users for future credit economy (Week 5)
ALTER TABLE public.users
  ADD COLUMN IF NOT EXISTS credits INTEGER NOT NULL DEFAULT 0;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'users_credits_non_negative'
  ) THEN
    ALTER TABLE public.users ADD CONSTRAINT users_credits_non_negative CHECK (credits >= 0);
  END IF;
END $$;
