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

-- 5. Sample hashtags
INSERT INTO public.hashtags (id, name, post_count) VALUES
  ('h0000000-0000-0000-0000-000000000001', 'studytips', 2),
  ('h0000000-0000-0000-0000-000000000002', 'cs101', 1),
  ('h0000000-0000-0000-0000-000000000003', 'midterm', 1),
  ('h0000000-0000-0000-0000-000000000004', 'linearalgebra', 1)
ON CONFLICT DO NOTHING;

-- 6. Sample posts (uses a deterministic UUID so seed is idempotent)
--    NOTE: user_id references must exist. When running seed after the test
--    user is created via Auth, replace the UUID below with the real test user id.
--    For now we use a placeholder that the handle_new_user trigger would create.
INSERT INTO public.posts (id, user_id, title, body, visibility, course_id, likes_count, comments_count) VALUES
  ('d0000000-0000-0000-0000-000000000001',
   (SELECT id FROM public.users LIMIT 1),
   'Chapter 5 study notes — CS101',
   'Here are my notes from chapter 5. Covers recursion, stacks, and queues. Hope they help for the midterm!',
   'public',
   'c0000000-0000-0000-0000-000000000001',
   0, 1),
  ('d0000000-0000-0000-0000-000000000002',
   (SELECT id FROM public.users LIMIT 1),
   'Linear Algebra cheat sheet',
   'Condensed formula sheet for eigenvectors, determinants, and matrix transformations.',
   'public',
   'c0000000-0000-0000-0000-000000000002',
   0, 0)
ON CONFLICT DO NOTHING;

-- 7. Link posts to hashtags
INSERT INTO public.post_hashtags (post_id, hashtag_id) VALUES
  ('d0000000-0000-0000-0000-000000000001', 'h0000000-0000-0000-0000-000000000001'),
  ('d0000000-0000-0000-0000-000000000001', 'h0000000-0000-0000-0000-000000000002'),
  ('d0000000-0000-0000-0000-000000000001', 'h0000000-0000-0000-0000-000000000003'),
  ('d0000000-0000-0000-0000-000000000002', 'h0000000-0000-0000-0000-000000000001'),
  ('d0000000-0000-0000-0000-000000000002', 'h0000000-0000-0000-0000-000000000004')
ON CONFLICT DO NOTHING;

-- 8. Sample comment
INSERT INTO public.comments (id, post_id, user_id, body) VALUES
  ('e0000000-0000-0000-0000-000000000001',
   'd0000000-0000-0000-0000-000000000001',
   (SELECT id FROM public.users LIMIT 1),
   'Great notes! The recursion section really helped me understand base cases.')
ON CONFLICT DO NOTHING;
