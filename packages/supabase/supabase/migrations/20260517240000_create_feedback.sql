-- Profile → Feedback section. UI labels are applied in migration
-- 20260518200000_feedback_friendly_column_names.sql.
--
-- Photos are NOT stored inline — the client uploads to `feedback-media`
-- and stores storage paths in the `Photos` text[] column.

CREATE TABLE IF NOT EXISTS public.feedback (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id           UUID REFERENCES public.users(id) ON DELETE SET NULL,
  feedback_type     TEXT NOT NULL,
  area              TEXT NOT NULL,
  area_other        TEXT,
  priority          TEXT NOT NULL,
  title             TEXT NOT NULL,
  body              TEXT NOT NULL,
  follow_up_enabled BOOLEAN NOT NULL DEFAULT FALSE,
  contact_email     TEXT,
  media_paths       TEXT[] NOT NULL DEFAULT '{}',
  app_version       TEXT,
  device_info       JSONB,
  status            TEXT NOT NULL DEFAULT 'new' CHECK (status IN ('new', 'triaged', 'in_progress', 'resolved', 'wont_fix')),
  created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT feedback_title_len CHECK (char_length(title) BETWEEN 1 AND 200),
  CONSTRAINT feedback_body_len  CHECK (char_length(body) BETWEEN 1 AND 5000)
);

CREATE INDEX IF NOT EXISTS idx_feedback_user_id     ON public.feedback(user_id);
CREATE INDEX IF NOT EXISTS idx_feedback_created_at  ON public.feedback(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_feedback_status      ON public.feedback(status);

-- Auto-bump updated_at when a maintainer changes status.
CREATE OR REPLACE FUNCTION public.set_feedback_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_feedback_updated_at ON public.feedback;
CREATE TRIGGER trg_feedback_updated_at
  BEFORE UPDATE ON public.feedback
  FOR EACH ROW EXECUTE FUNCTION public.set_feedback_updated_at();

ALTER TABLE public.feedback ENABLE ROW LEVEL SECURITY;

-- `submit-feedback` calls Supabase with the user's bearer token (see
-- `functions/_shared/auth.ts`), so the INSERT runs as the authenticated
-- user under RLS. Same pattern as `public.posts`: grant SELECT/INSERT
-- on rows the user owns, leave UPDATE/DELETE for the support team to
-- run through the service role.
CREATE POLICY "Users read their own feedback"
  ON public.feedback FOR SELECT
  USING (auth.uid() = user_id);

CREATE POLICY "Users insert their own feedback"
  ON public.feedback FOR INSERT
  WITH CHECK (auth.uid() = user_id);
