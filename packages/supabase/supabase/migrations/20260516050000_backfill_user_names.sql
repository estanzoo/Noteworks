-- Backfill display names for users whose `name` column is NULL or empty.
-- Pre-existing test rows from before the `handle_new_user` trigger landed
-- show up as "Anonymous" on community posts/comments; pulling the email
-- prefix gives every author a stable, recognisable label without forcing
-- the user to re-edit their profile.
UPDATE public.users
SET name = COALESCE(NULLIF(split_part(email, '@', 1), ''), 'Student')
WHERE name IS NULL OR length(btrim(name)) = 0;
