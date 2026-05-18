-- Profile → Feedback section needs a real durable home. Mirrors the
-- shape submitted by `apps/ios/Noteworks/.../ProfileViewModel.swift`
-- (type, area, priority, summary, body, follow-up email, photo refs).
--
-- Photos are NOT stored inline — the client uploads them to the
-- `feedback-media` bucket first and passes back the storage paths in
-- the `media_paths[]` array. That keeps the table cheap to query.

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

-- Users can read what they submitted. Insert goes through the edge
-- function (service role), so we don't grant INSERT to authenticated.
CREATE POLICY "Users read their own feedback"
  ON public.feedback FOR SELECT
  USING (auth.uid() = user_id);
