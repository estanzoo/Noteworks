-- Community feature: posts, comments, hashtags
-- =============================================

-- 1. TABLES
-- ---------

CREATE TABLE public.posts (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id     UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  title       TEXT NOT NULL,
  body        TEXT NOT NULL,
  course_id   UUID REFERENCES public.courses(id) ON DELETE SET NULL,
  visibility  TEXT NOT NULL DEFAULT 'public' CHECK (visibility IN ('public', 'private')),
  deleted_at  TIMESTAMPTZ,
  likes_count    INTEGER NOT NULL DEFAULT 0 CHECK (likes_count >= 0),
  comments_count INTEGER NOT NULL DEFAULT 0 CHECK (comments_count >= 0),
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE public.post_attachments (
  post_id    UUID NOT NULL REFERENCES public.posts(id) ON DELETE CASCADE,
  note_id    UUID NOT NULL REFERENCES public.notes(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (post_id, note_id)
);

CREATE TABLE public.hashtags (
  id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name       TEXT UNIQUE NOT NULL,
  post_count INTEGER NOT NULL DEFAULT 0 CHECK (post_count >= 0),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE public.post_hashtags (
  post_id    UUID NOT NULL REFERENCES public.posts(id) ON DELETE CASCADE,
  hashtag_id UUID NOT NULL REFERENCES public.hashtags(id) ON DELETE CASCADE,
  PRIMARY KEY (post_id, hashtag_id)
);

CREATE TABLE public.post_likes (
  post_id    UUID NOT NULL REFERENCES public.posts(id) ON DELETE CASCADE,
  user_id    UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (post_id, user_id)
);

CREATE TABLE public.comments (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  post_id           UUID NOT NULL REFERENCES public.posts(id) ON DELETE CASCADE,
  user_id           UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  parent_comment_id UUID REFERENCES public.comments(id) ON DELETE CASCADE,
  body              TEXT NOT NULL,
  likes_count       INTEGER NOT NULL DEFAULT 0 CHECK (likes_count >= 0),
  visibility        TEXT NOT NULL DEFAULT 'public' CHECK (visibility IN ('public', 'private')),
  created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at        TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 2. INDEXES
-- ----------

CREATE INDEX idx_posts_user_id ON public.posts(user_id);
CREATE INDEX idx_posts_course_id ON public.posts(course_id) WHERE course_id IS NOT NULL;
CREATE INDEX idx_posts_created_at ON public.posts(created_at DESC) WHERE deleted_at IS NULL;
CREATE INDEX idx_posts_visibility_created ON public.posts(visibility, created_at DESC) WHERE deleted_at IS NULL;
CREATE INDEX idx_comments_post_id ON public.comments(post_id);
CREATE INDEX idx_comments_parent ON public.comments(parent_comment_id) WHERE parent_comment_id IS NOT NULL;
CREATE INDEX idx_hashtags_name ON public.hashtags(name);
CREATE INDEX idx_post_likes_user ON public.post_likes(user_id);

-- 3. TRIGGER FUNCTIONS
-- --------------------

-- Auto-update posts.updated_at
CREATE OR REPLACE FUNCTION public.set_post_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_posts_updated_at
  BEFORE UPDATE ON public.posts
  FOR EACH ROW EXECUTE FUNCTION public.set_post_updated_at();

-- Sync posts.likes_count on post_likes INSERT/DELETE
CREATE OR REPLACE FUNCTION public.sync_post_likes_count()
RETURNS TRIGGER AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    UPDATE public.posts SET likes_count = likes_count + 1 WHERE id = NEW.post_id;
    RETURN NEW;
  ELSIF TG_OP = 'DELETE' THEN
    UPDATE public.posts SET likes_count = likes_count - 1 WHERE id = OLD.post_id;
    RETURN OLD;
  END IF;
  RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_post_likes_count
  AFTER INSERT OR DELETE ON public.post_likes
  FOR EACH ROW EXECUTE FUNCTION public.sync_post_likes_count();

-- Sync posts.comments_count on comments INSERT/DELETE
CREATE OR REPLACE FUNCTION public.sync_post_comments_count()
RETURNS TRIGGER AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    UPDATE public.posts SET comments_count = comments_count + 1 WHERE id = NEW.post_id;
    RETURN NEW;
  ELSIF TG_OP = 'DELETE' THEN
    UPDATE public.posts SET comments_count = comments_count - 1 WHERE id = OLD.post_id;
    RETURN OLD;
  END IF;
  RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_post_comments_count
  AFTER INSERT OR DELETE ON public.comments
  FOR EACH ROW EXECUTE FUNCTION public.sync_post_comments_count();

-- Sync hashtags.post_count on post_hashtags INSERT/DELETE
CREATE OR REPLACE FUNCTION public.sync_hashtag_post_count()
RETURNS TRIGGER AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    UPDATE public.hashtags SET post_count = post_count + 1 WHERE id = NEW.hashtag_id;
    RETURN NEW;
  ELSIF TG_OP = 'DELETE' THEN
    UPDATE public.hashtags SET post_count = post_count - 1 WHERE id = OLD.hashtag_id;
    RETURN OLD;
  END IF;
  RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_hashtag_post_count
  AFTER INSERT OR DELETE ON public.post_hashtags
  FOR EACH ROW EXECUTE FUNCTION public.sync_hashtag_post_count();

-- 4. ROW LEVEL SECURITY
-- ---------------------

ALTER TABLE public.posts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.post_attachments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.hashtags ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.post_hashtags ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.post_likes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.comments ENABLE ROW LEVEL SECURITY;

-- posts: SELECT public non-deleted posts, or own posts
CREATE POLICY "Anyone can read public non-deleted posts"
  ON public.posts FOR SELECT
  USING (
    (visibility = 'public' AND deleted_at IS NULL)
    OR user_id = auth.uid()
  );

CREATE POLICY "Users can insert own posts"
  ON public.posts FOR INSERT
  WITH CHECK (user_id = auth.uid());

CREATE POLICY "Users can update own posts"
  ON public.posts FOR UPDATE
  USING (user_id = auth.uid());

CREATE POLICY "Users can delete own posts"
  ON public.posts FOR DELETE
  USING (user_id = auth.uid());

-- post_attachments: readable if user can see the post
CREATE POLICY "Readable if post is visible"
  ON public.post_attachments FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.posts p
      WHERE p.id = post_id
        AND ((p.visibility = 'public' AND p.deleted_at IS NULL) OR p.user_id = auth.uid())
    )
  );

CREATE POLICY "Owner can manage attachments"
  ON public.post_attachments FOR INSERT
  WITH CHECK (
    EXISTS (SELECT 1 FROM public.posts WHERE id = post_id AND user_id = auth.uid())
  );

CREATE POLICY "Owner can delete attachments"
  ON public.post_attachments FOR DELETE
  USING (
    EXISTS (SELECT 1 FROM public.posts WHERE id = post_id AND user_id = auth.uid())
  );

-- hashtags: all authenticated can read and insert
CREATE POLICY "Authenticated can read hashtags"
  ON public.hashtags FOR SELECT
  USING (true);

CREATE POLICY "Authenticated can insert hashtags"
  ON public.hashtags FOR INSERT
  WITH CHECK (true);

-- post_hashtags: readable if post visible
CREATE POLICY "Readable if post is visible"
  ON public.post_hashtags FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.posts p
      WHERE p.id = post_id
        AND ((p.visibility = 'public' AND p.deleted_at IS NULL) OR p.user_id = auth.uid())
    )
  );

CREATE POLICY "Owner can manage post hashtags"
  ON public.post_hashtags FOR INSERT
  WITH CHECK (
    EXISTS (SELECT 1 FROM public.posts WHERE id = post_id AND user_id = auth.uid())
  );

CREATE POLICY "Owner can delete post hashtags"
  ON public.post_hashtags FOR DELETE
  USING (
    EXISTS (SELECT 1 FROM public.posts WHERE id = post_id AND user_id = auth.uid())
  );

-- post_likes: all authenticated can read; own user can insert/delete
CREATE POLICY "Authenticated can read likes"
  ON public.post_likes FOR SELECT
  USING (true);

CREATE POLICY "Users can insert own likes"
  ON public.post_likes FOR INSERT
  WITH CHECK (user_id = auth.uid());

CREATE POLICY "Users can delete own likes"
  ON public.post_likes FOR DELETE
  USING (user_id = auth.uid());

-- comments: visible if post is visible and comment is public (or own)
CREATE POLICY "Readable if post visible and comment public or own"
  ON public.comments FOR SELECT
  USING (
    (visibility = 'public' OR user_id = auth.uid())
    AND EXISTS (
      SELECT 1 FROM public.posts p
      WHERE p.id = post_id
        AND ((p.visibility = 'public' AND p.deleted_at IS NULL) OR p.user_id = auth.uid())
    )
  );

CREATE POLICY "Authenticated can insert comments"
  ON public.comments FOR INSERT
  WITH CHECK (user_id = auth.uid());

CREATE POLICY "Users can update own comments"
  ON public.comments FOR UPDATE
  USING (user_id = auth.uid());

CREATE POLICY "Users can delete own comments"
  ON public.comments FOR DELETE
  USING (user_id = auth.uid());
