-- Enable Row Level Security on public.users
ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;

-- Users can read only their own row
CREATE POLICY "Users can read own row"
    ON public.users
    FOR SELECT
    USING (auth.uid() = id);

-- Users can update only their own row
CREATE POLICY "Users can update own row"
    ON public.users
    FOR UPDATE
    USING (auth.uid() = id)
    WITH CHECK (auth.uid() = id);

-- Allow insert for the authenticated user's own row (e.g. when profile is created on signup)
CREATE POLICY "Users can insert own row"
    ON public.users
    FOR INSERT
    WITH CHECK (auth.uid() = id);

-- Optional: no DELETE policy = users cannot delete their profile row via RLS
-- Add a policy if you want to allow self-deletion.
