-- Heal users whose `auth.users` row exists but whose `public.users` row is
-- missing, and make the new-user trigger robust enough that we never strand
-- another account the same way.
--
-- Discovered while debugging "User profile not found" on the onboarding
-- "Any Field of Interests?" step. Apple Sign In hands back a session for
-- a pre-existing `auth.users` row (Apple reuses the same `sub` across
-- logins on the same device), but two historical accounts never received a
-- matching `public.users` row — most likely because an earlier version of
-- the trigger raised on a transient error or a unique-constraint clash and
-- aborted silently. `submit-onboarding`'s UPDATE then matched zero rows and
-- returned the 404 the user is seeing.

-- 1. Backfill any current orphans so the affected users can finish
--    onboarding immediately after this migration runs. `ON CONFLICT
--    DO NOTHING` keeps the statement safe to re-run.
INSERT INTO public.users (id, email, name)
SELECT
    a.id,
    COALESCE(NULLIF(a.email, ''), a.id::text || '@noreply.local'),
    COALESCE(
        NULLIF(a.raw_user_meta_data->>'name', ''),
        NULLIF(a.email, ''),
        'Noteworks User'
    )
FROM auth.users a
LEFT JOIN public.users p ON p.id = a.id
WHERE p.id IS NULL
ON CONFLICT (id) DO NOTHING;

-- 2. Replace the trigger function so future inserts can't strand a user:
--    * Tolerate a NULL/empty email by falling back to a synthetic placeholder
--      (every Apple "Hide My Email" relay we've seen comes back with the
--      `@privaterelay.appleid.com` address, but we don't want one weird
--      provider config to break sign-in for everyone).
--    * `ON CONFLICT (id) DO NOTHING` makes the trigger re-runnable after
--      a manual backfill / partial recovery and prevents PK clashes from
--      aborting the auth insert.
--    * `EXCEPTION WHEN OTHERS` guarantees the trigger never blocks the
--      auth.users insert itself — losing the public.users row is recoverable
--      (submit-onboarding upserts), losing the auth.users row is not.
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    BEGIN
        INSERT INTO public.users (id, email, name)
        VALUES (
            NEW.id,
            COALESCE(NULLIF(NEW.email, ''), NEW.id::text || '@noreply.local'),
            COALESCE(
                NULLIF(NEW.raw_user_meta_data->>'name', ''),
                NULLIF(NEW.email, ''),
                'Noteworks User'
            )
        )
        ON CONFLICT (id) DO NOTHING;
    EXCEPTION WHEN OTHERS THEN
        -- Swallow any unexpected failure so the auth user is still created.
        -- `submit-onboarding` upserts, so a later submission will self-heal
        -- and we'd rather have a recoverable orphan than no account at all.
        RAISE WARNING 'handle_new_user failed for %: %', NEW.id, SQLERRM;
    END;
    RETURN NEW;
END;
$$;
