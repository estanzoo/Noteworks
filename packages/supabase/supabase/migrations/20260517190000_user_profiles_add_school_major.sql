-- Expose `school_affiliation` and `major` on the public-profile view so
-- the community post detail header can show "Royal Academy of Arts /
-- MA Information Experience Design" under each author's name (matches
-- the updated NoteWorks_UI 3 community detail mock).
--
-- These columns are already considered safe-to-publish in the product
-- (the Profile screen surfaces them on every user's own page) and the
-- view is the only path community joins use for foreign authors —
-- the base `public.users` table still keeps its strict per-user RLS
-- on the more sensitive fields (email, credits, school_email, …).

CREATE OR REPLACE VIEW public.user_profiles AS
    SELECT id, name, avatar_url, school_affiliation, major
    FROM public.users;

ALTER VIEW public.user_profiles SET (security_invoker = false);

REVOKE ALL ON public.user_profiles FROM PUBLIC;
GRANT SELECT ON public.user_profiles TO authenticated, anon;
