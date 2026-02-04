-- Enable RLS on all remaining public tables
ALTER TABLE public.schools ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.courses ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.school_courses ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.school_enrollments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.course_enrollments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.notes ENABLE ROW LEVEL SECURITY;

-- Schools: authenticated users can read (browse); no write policies = service role only for writes
CREATE POLICY "Authenticated can read schools"
    ON public.schools
    FOR SELECT
    TO authenticated
    USING (true);

-- Courses: same
CREATE POLICY "Authenticated can read courses"
    ON public.courses
    FOR SELECT
    TO authenticated
    USING (true);

-- School–course junction: authenticated can read
CREATE POLICY "Authenticated can read school_courses"
    ON public.school_courses
    FOR SELECT
    TO authenticated
    USING (true);

-- School enrollments: users see and manage only their own rows
CREATE POLICY "Users can read own school enrollments"
    ON public.school_enrollments
    FOR SELECT
    TO authenticated
    USING (auth.uid() = user_id);

CREATE POLICY "Users can insert own school enrollment"
    ON public.school_enrollments
    FOR INSERT
    TO authenticated
    WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can delete own school enrollment"
    ON public.school_enrollments
    FOR DELETE
    TO authenticated
    USING (auth.uid() = user_id);

-- Course enrollments: same
CREATE POLICY "Users can read own course enrollments"
    ON public.course_enrollments
    FOR SELECT
    TO authenticated
    USING (auth.uid() = user_id);

CREATE POLICY "Users can insert own course enrollment"
    ON public.course_enrollments
    FOR INSERT
    TO authenticated
    WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can delete own course enrollment"
    ON public.course_enrollments
    FOR DELETE
    TO authenticated
    USING (auth.uid() = user_id);

-- Notes: users can read own notes or notes in courses they're enrolled in
CREATE POLICY "Users can read own notes or notes in enrolled courses"
    ON public.notes
    FOR SELECT
    TO authenticated
    USING (
        auth.uid() = user_id
        OR EXISTS (
            SELECT 1 FROM public.course_enrollments ce
            WHERE ce.course_id = notes.course_id AND ce.user_id = auth.uid()
        )
    );

CREATE POLICY "Users can insert own notes"
    ON public.notes
    FOR INSERT
    TO authenticated
    WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update own notes"
    ON public.notes
    FOR UPDATE
    TO authenticated
    USING (auth.uid() = user_id)
    WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can delete own notes"
    ON public.notes
    FOR DELETE
    TO authenticated
    USING (auth.uid() = user_id);
