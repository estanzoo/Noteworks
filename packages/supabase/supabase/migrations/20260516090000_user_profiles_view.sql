-- Public profile view for community joins.
--
-- The base `public.users` table has a strict "you can only read your own row"
-- RLS policy. That's correct for sensitive fields (email, school, credits…)
-- but it breaks every community surface, because the embedded
-- `author:users!posts_user_id_fkey(...)` join in get-posts / get-post /
-- search-posts / get-comments / create-comment returns NULL for every
-- author that isn't the current user. The iOS app then falls back to
-- "Student" for every post written by somebody else.
--
-- Fix: expose ONLY the safe public-profile columns (id, name, avatar_url)
-- via a view. Because the view is created by the postgres role (its
-- owner) and `security_invoker` defaults to false on Postgres < 15,
-- queries against it bypass the underlying RLS on `public.users` and
-- return every row to any caller granted SELECT on the view. We grant
-- that to `authenticated` and `anon` so PostgREST embedded joins work
-- end-to-end.

CREATE OR REPLACE VIEW public.user_profiles AS
    SELECT id, name, avatar_url
    FROM public.users;

-- Ensure the view runs with the definer's permissions on Postgres 15+ too.
ALTER VIEW public.user_profiles SET (security_invoker = false);

REVOKE ALL ON public.user_profiles FROM PUBLIC;
GRANT SELECT ON public.user_profiles TO authenticated, anon;
