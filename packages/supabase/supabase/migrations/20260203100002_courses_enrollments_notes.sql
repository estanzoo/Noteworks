-- Add course_code and image to courses
ALTER TABLE public.courses
    ADD COLUMN IF NOT EXISTS code TEXT UNIQUE,
    ADD COLUMN IF NOT EXISTS image TEXT;

-- Junction: users enrolled in each course (course -> many users)
CREATE TABLE public.course_enrollments (
    course_id UUID NOT NULL REFERENCES public.courses(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    enrolled_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (course_id, user_id)
);

-- Notes uploaded to a course (course -> many notes; each note has an uploader)
CREATE TABLE public.notes (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    course_id UUID NOT NULL REFERENCES public.courses(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    title TEXT NOT NULL,
    metadata JSONB,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_course_enrollments_course_id ON public.course_enrollments(course_id);
CREATE INDEX idx_course_enrollments_user_id ON public.course_enrollments(user_id);
CREATE INDEX idx_notes_course_id ON public.notes(course_id);
CREATE INDEX idx_notes_user_id ON public.notes(user_id);
