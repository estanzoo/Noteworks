# Seed data for hosted Supabase

Use these CSVs to populate your **hosted** project when `db:reset` (and thus `seed.sql`) doesn’t run there.

## Import order

1. **schools** → **courses** → **school_courses** (schools and courses first; school_courses references both).

## How to import in Supabase Dashboard

1. Open your project: **https://supabase.com/dashboard/project/canhewvuprjwmpopcloj**
2. Go to **Table Editor**.
3. For each table:
   - Select the table (`schools`, then `courses`, then `school_courses`).
   - Use **Insert** → **Import data from CSV** (or **Insert row** and paste if CSV import isn’t available).
   - Choose the CSV and map columns if asked. Column names match the CSV headers.

## Alternative: run SQL in SQL Editor

If CSV import is awkward, run this in **SQL Editor** (same order: schools → courses → school_courses):

```sql
-- Schools
INSERT INTO public.schools (id, name, location) VALUES
  ('a0000000-0000-0000-0000-000000000001', 'Demo University', 'New York, NY'),
  ('a0000000-0000-0000-0000-000000000002', 'Test College', 'San Francisco, CA'),
  ('a0000000-0000-0000-0000-000000000003', 'State Tech', 'Chicago IL'),
  ('a0000000-0000-0000-0000-000000000004', 'Liberal Arts College', 'Boston MA')
ON CONFLICT (id) DO NOTHING;

-- Courses
INSERT INTO public.courses (id, name, code, description) VALUES
  ('c0000000-0000-0000-0000-000000000001', 'Introduction to Computer Science', 'CS101', 'Basics of computing and programming'),
  ('c0000000-0000-0000-0000-000000000002', 'Linear Algebra', 'MATH201', 'Vectors, matrices and linear transformations'),
  ('c0000000-0000-0000-0000-000000000003', 'Organic Chemistry', 'CHEM301', 'Structure and reactions of organic compounds'),
  ('c0000000-0000-0000-0000-000000000004', 'Data Structures', 'CS201', 'Trees, graphs and algorithms'),
  ('c0000000-0000-0000-0000-000000000005', 'Calculus I', 'MATH101', 'Limits, derivatives and integrals')
ON CONFLICT (id) DO NOTHING;

-- School–course links
INSERT INTO public.school_courses (school_id, course_id) VALUES
  ('a0000000-0000-0000-0000-000000000001', 'c0000000-0000-0000-0000-000000000001'),
  ('a0000000-0000-0000-0000-000000000001', 'c0000000-0000-0000-0000-000000000002'),
  ('a0000000-0000-0000-0000-000000000001', 'c0000000-0000-0000-0000-000000000004'),
  ('a0000000-0000-0000-0000-000000000001', 'c0000000-0000-0000-0000-000000000005'),
  ('a0000000-0000-0000-0000-000000000002', 'c0000000-0000-0000-0000-000000000003'),
  ('a0000000-0000-0000-0000-000000000002', 'c0000000-0000-0000-0000-000000000005'),
  ('a0000000-0000-0000-0000-000000000003', 'c0000000-0000-0000-0000-000000000001'),
  ('a0000000-0000-0000-0000-000000000003', 'c0000000-0000-0000-0000-000000000002'),
  ('a0000000-0000-0000-0000-000000000004', 'c0000000-0000-0000-0000-000000000002'),
  ('a0000000-0000-0000-0000-000000000004', 'c0000000-0000-0000-0000-000000000003')
ON CONFLICT (school_id, course_id) DO NOTHING;
```

## Note on `public.users`

`public.users` is filled by the **trigger** when someone signs up via **Authentication**. There is no CSV for it. To get a row there, sign up (or create a user) in **Authentication** in the dashboard; the trigger will insert the corresponding row into `public.users`.
