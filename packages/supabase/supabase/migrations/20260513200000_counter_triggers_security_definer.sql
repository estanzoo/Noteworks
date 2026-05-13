-- Fix counter-sync triggers to run with definer privileges so they can
-- bypass row-level security.
--
-- The four trigger functions below all maintain denormalized counters
-- (`posts.likes_count`, `posts.comments_count`, `hashtags.post_count`,
-- `comments.likes_count`) by issuing `UPDATE` statements against tables
-- that have RLS enabled. Without `SECURITY DEFINER`, the UPDATEs run as
-- the invoking user — and the RLS policies on those tables only allow a
-- user to update their **own** rows. So when user A likes user B's post,
-- the UPDATE against `posts` is silently filtered to 0 rows, the trigger
-- succeeds, and the counter stays stuck at its old value.
--
-- Marking these functions `SECURITY DEFINER` makes them run as the
-- function's owner (typically `postgres`), which bypasses RLS. This is
-- the canonical Postgres + Supabase pattern for counter-keeping triggers.
-- We also lock down `search_path` so a future role-shadowing schema can't
-- intercept the table references — standard hardening for definer code.

CREATE OR REPLACE FUNCTION public.sync_post_likes_count()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
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
$$;

CREATE OR REPLACE FUNCTION public.sync_post_comments_count()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
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
$$;

CREATE OR REPLACE FUNCTION public.sync_hashtag_post_count()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
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
$$;

CREATE OR REPLACE FUNCTION public.sync_comment_likes_count()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
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
$$;

-- Backfill: any rows that were inserted into post_likes / comment_likes /
-- post_hashtags / comments while the triggers were running under the
-- invoker's privileges produced 0-row UPDATEs, so the existing counters
-- are stale. Recompute them from the source-of-truth tables.

UPDATE public.posts p
SET likes_count = sub.cnt
FROM (
  SELECT post_id, COUNT(*)::int AS cnt
  FROM public.post_likes
  GROUP BY post_id
) sub
WHERE p.id = sub.post_id AND p.likes_count <> sub.cnt;

UPDATE public.posts p
SET likes_count = 0
WHERE p.likes_count <> 0
  AND NOT EXISTS (SELECT 1 FROM public.post_likes pl WHERE pl.post_id = p.id);

UPDATE public.posts p
SET comments_count = sub.cnt
FROM (
  SELECT post_id, COUNT(*)::int AS cnt
  FROM public.comments
  GROUP BY post_id
) sub
WHERE p.id = sub.post_id AND p.comments_count <> sub.cnt;

UPDATE public.posts p
SET comments_count = 0
WHERE p.comments_count <> 0
  AND NOT EXISTS (SELECT 1 FROM public.comments c WHERE c.post_id = p.id);

UPDATE public.hashtags h
SET post_count = sub.cnt
FROM (
  SELECT hashtag_id, COUNT(*)::int AS cnt
  FROM public.post_hashtags
  GROUP BY hashtag_id
) sub
WHERE h.id = sub.hashtag_id AND h.post_count <> sub.cnt;

UPDATE public.hashtags h
SET post_count = 0
WHERE h.post_count <> 0
  AND NOT EXISTS (SELECT 1 FROM public.post_hashtags ph WHERE ph.hashtag_id = h.id);

UPDATE public.comments c
SET likes_count = sub.cnt
FROM (
  SELECT comment_id, COUNT(*)::int AS cnt
  FROM public.comment_likes
  GROUP BY comment_id
) sub
WHERE c.id = sub.comment_id AND c.likes_count <> sub.cnt;

UPDATE public.comments c
SET likes_count = 0
WHERE c.likes_count <> 0
  AND NOT EXISTS (SELECT 1 FROM public.comment_likes cl WHERE cl.comment_id = c.id);
