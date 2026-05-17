-- Add avatar_url to public.users.
-- The column stores the public URL of the user's profile photo in the
-- `avatars` storage bucket (see 20260516040000_create_avatars_bucket.sql).
-- Nullable — most users won't have set a photo yet.
ALTER TABLE public.users
    ADD COLUMN IF NOT EXISTS avatar_url TEXT;
