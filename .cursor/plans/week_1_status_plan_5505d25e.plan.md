---
name: Week 1 Status Plan
overview: "A status plan for Week 1 (Foundation & Authentication) of the Noteworks backend: what is already done versus what remains, with no code implementation."
todos: []
isProject: false
---

# Week 1: Foundation & Authentication — Status Plan

This plan compares the [6-Week Backend Plan](docs/backend/Noteworks_Backend_6Week_Plan.md) Week 1 scope to your current repo and lists completed work and remaining tasks.

---

## Week 1 scope (from the doc)

- **Days 1–2:** Project setup (Supabase, Git, env/secrets, CLI, migrations, CI/CD)
- **Days 3–4:** Core database schema (users, schools, courses, user_courses)
- **Day 5:** Authentication (Apple/Google OAuth, RLS, onboarding flow, session management)

---

## What you have already finished

### Days 1–2: Project setup (mostly done)


| Item                              | Status | Evidence                                                                                                                                                                                                                                               |
| --------------------------------- | ------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Supabase project / local setup    | Done   | [config.toml](packages/supabase/supabase/config.toml) with API, DB, Auth, Storage, Realtime; PostgreSQL 15                                                                                                                                             |
| Git repo + branching              | Done   | Repo exists; doc mentions main/develop/feature (assumed in use)                                                                                                                                                                                        |
| Supabase CLI + migration workflow | Done   | Root [package.json](package.json): `db:start`, `db:stop`, `db:reset`, `db:migrate`, `types:generate`; [packages/supabase](packages/supabase) has `migrate:new`, `migrate:up`                                                                           |
| Version-controlled migrations     | Done   | Single migration [20260201155932_initial_schema.sql](packages/supabase/supabase/migrations/20260201155932_initial_schema.sql)                                                                                                                          |
| CI/CD (schema + types validation) | Done   | [.github/workflows/sync-types.yml](.github/workflows/sync-types.yml): Supabase start, gen types, verify shared-types build on PR/push for `packages/supabase/**`, `packages/shared-types/**`                                                           |
| Shared TypeScript types           | Done   | [packages/shared-types](packages/shared-types): [database.types.ts](packages/shared-types/database.types.ts) (placeholder aligned to current schema), [api.types.ts](packages/shared-types/api.types.ts), [models.ts](packages/shared-types/models.ts) |


### Days 3–4: Core schema (partially done)


| Item                 | Status   | Evidence                                                                                                                             |
| -------------------- | -------- | ------------------------------------------------------------------------------------------------------------------------------------ |
| `users` table        | Partial  | Exists with `id`, `email`, `name`, `created_at`, `updated_at` and `REFERENCES auth.users`. **Missing:** `credits` (integer) per plan |
| `schools` table      | Not done | Not in migration                                                                                                                     |
| `courses` table      | Not done | Not in migration                                                                                                                     |
| `user_courses` table | Not done | Not in migration                                                                                                                     |


### Day 5: Authentication (partially done)


| Item                                    | Status               | Evidence                                                                                                                                                    |
| --------------------------------------- | -------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Apple OAuth config (dashboard/local)    | Configured in config | [config.toml](packages/supabase/supabase/config.toml) has `[auth.external.apple]` with `client_id = "env(APPLE_CLIENT_ID)"`, `secret = "env(APPLE_SECRET)"` |
| Google OAuth config                     | Configured in config | Same file has `[auth.external.google]` with env-based client_id/secret                                                                                      |
| RLS on `users`                          | Not done             | No `ENABLE ROW LEVEL SECURITY` or `CREATE POLICY` in repo                                                                                                   |
| Onboarding flow (school, courses, year) | Not done             | No backend implementation                                                                                                                                   |
| Session / token refresh                 | Not done             | Plan item; typically client + Supabase Auth; no explicit backend work found                                                                                 |


---

## What you still need to do

### 1. Environment and secrets (Days 1–2)

- **Supabase Vault / env for OAuth:** Plan calls for “environment variables and secrets management using Supabase Vault.” Config already uses `env(APPLE_CLIENT_ID)`, etc.; you still need to:
  - Document where to set these (e.g. `.env` for local, Supabase dashboard or Vault for hosted).
  - Optionally add a small “Secrets & env” section to the repo or backend doc (what to set for Apple/Google, no values committed).
- **Production + staging:** Plan mentions “production + staging environments.” Confirm you have (or will create) two Supabase projects and document which env vars go where.

### 2. Core database schema (Days 3–4)

Add to migrations (new migration(s) or extend the initial one; prefer new for clarity):

- `**users`:** Add column `credits INTEGER` (default 0 or NOT NULL as per product need).
- `**schools`:**  
`id UUID PRIMARY KEY`, `name TEXT`, `country TEXT`, `created_at TIMESTAMPTZ DEFAULT NOW()` (and indexes if you have a pattern).
- `**courses`:**  
`id UUID PRIMARY KEY`, `school_id UUID REFERENCES schools(id)`, `code TEXT`, `name TEXT`, `description TEXT`, `created_at TIMESTAMPTZ DEFAULT NOW()`, plus indexes (e.g. `school_id`, `code`).
- `**user_courses`:**  
`user_id UUID REFERENCES users(id)`, `course_id UUID REFERENCES courses(id)`, `year INTEGER` (or TEXT), `role TEXT` (e.g. student/instructor), `joined_at TIMESTAMPTZ`, composite primary key `(user_id, course_id)` and indexes for common lookups (e.g. `course_id`, `user_id`).

After changing schema, run `pnpm types:generate` (and commit updated [database.types.ts](packages/shared-types/database.types.ts) or rely on CI; your workflow already validates type generation).

### 3. Row Level Security — RLS (Day 5)

- Enable RLS on `public.users`:  
`ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;`
- Add policies so that:
  - Users can read/update their own row (e.g. `auth.uid() = id`).
  - Optionally: only the service role or auth hooks can insert a row for the new user (to align with “extends auth.users”).
- Decide RLS for `schools`, `courses`, `user_courses` (e.g. schools/courses readable by authenticated users; user_courses scoped by `auth.uid()`). Add `ENABLE ROW LEVEL SECURITY` and `CREATE POLICY` statements in a migration.

### 4. Authentication and onboarding (Day 5)

- **OAuth:** Ensure Apple and Google OAuth are fully set up in the Supabase project(s) (redirect URIs, credentials in env/Vault). No code change required if config is already correct; this is verification and doc.
- **Onboarding data flow:** Implement the “user onboarding data collection flow (school, courses, year)”:
  - Backend: e.g. Edge Function or direct Postgres (with RLS) that creates/updates `user_courses` and optionally links user to school. If you need a “selected school” on the user, add a column or use `user_courses` as the source of truth.
  - Client: call this after first sign-in (and optionally refresh when user changes selection). No code in repo yet—plan only.
- **Session and token refresh:** Rely on Supabase client SDK on iOS for session management and refresh; document that “session management and token refresh” is handled by the client. If you add a custom middleware or Edge Function that uses tokens, add that to the plan later.
- **Testing:** “Test authentication flows on iOS simulator and device” — manual/QA task; no backend code.

### 5. Optional improvements

- **Migration script:** [scripts/generate-migration.sh](scripts/generate-migration.sh) is empty. You can add a one-liner that runs `supabase migration new` (or similar) from the repo root so “create migration workflow” is fully scripted.
- **Seed data:** [packages/supabase/supabase/seed.sql](packages/supabase/supabase/seed.sql) is a stub. For Week 1 you can add minimal seed data (e.g. one school, one course) to test onboarding and RLS.

---

## Suggested order of work

1. **Secrets & env:** Document and set Apple/Google OAuth env vars (and Vault if using hosted Supabase).
2. **Schema:** Add `credits` to `users`; add `schools`, `courses`, `user_courses` in a new migration; run `pnpm types:generate` and commit type changes if desired.
3. **RLS:** Add RLS and policies for `users`, then for `schools`/`courses`/`user_courses` in a migration.
4. **Onboarding:** Implement backend for “school, courses, year” (e.g. Edge Function or secured mutations) and document the client flow.
5. **Verification:** Test Apple/Google sign-in and onboarding on iOS; confirm RLS by testing as different users.

---

## Week 1 deliverables checklist (from doc)


| Deliverable                                                | Status                                                                         |
| ---------------------------------------------------------- | ------------------------------------------------------------------------------ |
| Database Schema v1.0 (core tables, relationships, indexes) | In progress — users exists; schools, courses, user_courses and credits missing |
| Authentication (Apple + Google OAuth end-to-end)           | Config ready; env/Vault and iOS testing pending                                |
| RLS policies (user data access control)                    | Not started                                                                    |
| Migration scripts (version-controlled)                     | Done                                                                           |
| Development environment (staging + production ready)       | Local ready; staging/prod Supabase projects to confirm/document                |


Once the schema and RLS migrations are in place and onboarding is implemented, you can mark Week 1 complete and move on to Week 2 (Notes & Storage).