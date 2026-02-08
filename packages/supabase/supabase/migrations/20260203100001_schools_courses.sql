-- Courses table (referenced by schools for courses offered)
CREATE TABLE public.courses (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL,
    code TEXT UNIQUE,
    description TEXT,
    image TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Schools table
CREATE TABLE public.schools (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL,
    location TEXT,
    image TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Junction: courses offered by each school (school -> many courses)
CREATE TABLE public.school_courses (
    school_id UUID NOT NULL REFERENCES public.schools(id) ON DELETE CASCADE,
    course_id UUID NOT NULL REFERENCES public.courses(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (school_id, course_id)
);

-- Junction: users enrolled in each school (school -> many users)
CREATE TABLE public.school_enrollments (
    school_id UUID NOT NULL REFERENCES public.schools(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    enrolled_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (school_id, user_id)
);

-- Indexes for common lookups
CREATE INDEX idx_school_courses_school_id ON public.school_courses(school_id);
CREATE INDEX idx_school_courses_course_id ON public.school_courses(course_id);
CREATE INDEX idx_school_enrollments_school_id ON public.school_enrollments(school_id);
CREATE INDEX idx_school_enrollments_user_id ON public.school_enrollments(user_id);
