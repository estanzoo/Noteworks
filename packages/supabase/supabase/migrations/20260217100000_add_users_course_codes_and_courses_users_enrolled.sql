-- Add course_codes to users (list of course codes the user is enrolled in)
ALTER TABLE public.users
  ADD COLUMN IF NOT EXISTS course_codes TEXT[] DEFAULT '{}';

-- Add users_enrolled count to courses (denormalized for quick display)
ALTER TABLE public.courses
  ADD COLUMN IF NOT EXISTS users_enrolled_count INTEGER NOT NULL DEFAULT 0;

-- Constraint: count cannot go negative (safety)
ALTER TABLE public.courses
  DROP CONSTRAINT IF EXISTS courses_users_enrolled_count_non_negative;
ALTER TABLE public.courses
  ADD CONSTRAINT courses_users_enrolled_count_non_negative CHECK (users_enrolled_count >= 0);

-- Trigger: increment course users_enrolled_count when a user enrolls
CREATE OR REPLACE FUNCTION public.increment_course_users_enrolled()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  UPDATE public.courses
  SET users_enrolled_count = users_enrolled_count + 1
  WHERE id = NEW.course_id;
  RETURN NEW;
END;
$$;

-- Trigger: decrement course users_enrolled_count when an enrollment is removed
CREATE OR REPLACE FUNCTION public.decrement_course_users_enrolled()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  UPDATE public.courses
  SET users_enrolled_count = GREATEST(0, users_enrolled_count - 1)
  WHERE id = OLD.course_id;
  RETURN OLD;
END;
$$;

DROP TRIGGER IF EXISTS on_course_enrollment_insert ON public.course_enrollments;
CREATE TRIGGER on_course_enrollment_insert
  AFTER INSERT ON public.course_enrollments
  FOR EACH ROW
  EXECUTE FUNCTION public.increment_course_users_enrolled();

DROP TRIGGER IF EXISTS on_course_enrollment_delete ON public.course_enrollments;
CREATE TRIGGER on_course_enrollment_delete
  AFTER DELETE ON public.course_enrollments
  FOR EACH ROW
  EXECUTE FUNCTION public.decrement_course_users_enrolled();

-- Backfill users_enrolled_count from current course_enrollments
UPDATE public.courses c
SET users_enrolled_count = COALESCE(
  (SELECT COUNT(*) FROM public.course_enrollments ce WHERE ce.course_id = c.id),
  0
);
