-- Seed data for local development
-- Run: pnpm db:reset   (this re-runs all migrations + seed)

-- 1. Create a test user in Supabase Auth (email: test@test.com / password: password123)
--    The handle_new_user trigger should auto-insert into public.users,
--    but we insert a fallback row below in case the trigger isn't active.

-- 2. Sample schools
INSERT INTO public.schools (id, name, location) VALUES
  ('a0000000-0000-0000-0000-000000000001', 'Demo University', 'New York, NY'),
  ('a0000000-0000-0000-0000-000000000002', 'Test College', 'San Francisco, CA')
ON CONFLICT DO NOTHING;

-- 3. Sample courses
INSERT INTO public.courses (id, name, code, description) VALUES
  ('c0000000-0000-0000-0000-000000000001', 'Introduction to Computer Science', 'CS101', 'Basics of computing and programming'),
  ('c0000000-0000-0000-0000-000000000002', 'Linear Algebra', 'MATH201', 'Vectors, matrices, and linear transformations'),
  ('c0000000-0000-0000-0000-000000000003', 'Organic Chemistry', 'CHEM301', 'Structure and reactions of organic compounds')
ON CONFLICT DO NOTHING;

-- 4. Link courses to school
INSERT INTO public.school_courses (school_id, course_id) VALUES
  ('a0000000-0000-0000-0000-000000000001', 'c0000000-0000-0000-0000-000000000001'),
  ('a0000000-0000-0000-0000-000000000001', 'c0000000-0000-0000-0000-000000000002'),
  ('a0000000-0000-0000-0000-000000000002', 'c0000000-0000-0000-0000-000000000003')
ON CONFLICT DO NOTHING;
