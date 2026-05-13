-- Comment likes: table, indexes, count-sync trigger, RLS
-- =======================================================

-- 1. TABLE
-- --------

CREATE TABLE public.comment_likes (
  comment_id UUID NOT NULL REFERENCES public.comments(id) ON DELETE CASCADE,
  user_id    UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (comment_id, user_id)
);

-- 2. INDEXES
-- ----------

CREATE INDEX idx_comment_likes_user ON public.comment_likes(user_id);

-- 3. TRIGGER: keep comments.likes_count in sync
-- ---------------------------------------------

CREATE OR REPLACE FUNCTION public.sync_comment_likes_count()
RETURNS TRIGGER AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    UPDATE public.comments SET likes_count = likes_count + 1 WHERE id = NEW.comment_id;
    RETURN NEW;
  ELSIF TG_OP = 'DELETE' THEN
    UPDATE public.comments SET likes_count = likes_count - 1 WHERE id = OLD.comment_id;
    RETURN OLD;
  END IF;
  RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_comment_likes_count
  AFTER INSERT OR DELETE ON public.comment_likes
  FOR EACH ROW EXECUTE FUNCTION public.sync_comment_likes_count();

-- 4. ROW LEVEL SECURITY
-- ---------------------

ALTER TABLE public.comment_likes ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Authenticated can read comment likes"
  ON public.comment_likes FOR SELECT
  USING (true);

CREATE POLICY "Users can insert own comment likes"
  ON public.comment_likes FOR INSERT
  WITH CHECK (user_id = auth.uid());

CREATE POLICY "Users can delete own comment likes"
  ON public.comment_likes FOR DELETE
  USING (user_id = auth.uid());
