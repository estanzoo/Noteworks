-- The original `feedback` migration (20260517240000) was written under
-- the assumption that the edge function would insert with the service
-- role. We actually call Supabase with the user's bearer token, so the
-- INSERT runs under RLS and was failing with "new row violates
-- row-level security policy for table feedback".
--
-- Mirror the pattern used by `public.posts`: let authenticated users
-- insert rows they own; UPDATE/DELETE stay restricted to service role.

DROP POLICY IF EXISTS "Users insert their own feedback" ON public.feedback;

CREATE POLICY "Users insert their own feedback"
  ON public.feedback FOR INSERT
  TO authenticated
  WITH CHECK (auth.uid() = user_id);
