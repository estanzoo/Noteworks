-- Add a `bio` column to `public.users` so the Profile → About You editor
-- can persist the short self-description that already lives in the hero
-- card. Kept as plain text (no length cap enforced at the DB layer — the
-- edge function is the single trim/cap source of truth).

ALTER TABLE public.users
  ADD COLUMN IF NOT EXISTS bio TEXT;

-- Expose `bio` on the public-profile view alongside school/major so the
-- community surfaces can fetch it for foreign users without widening
-- RLS on the underlying `public.users` table.
CREATE OR REPLACE VIEW public.user_profiles AS
    SELECT id, name, avatar_url, school_affiliation, major, bio
    FROM public.users;

ALTER VIEW public.user_profiles SET (security_invoker = false);

REVOKE ALL ON public.user_profiles FROM PUBLIC;
GRANT SELECT ON public.user_profiles TO authenticated, anon;
