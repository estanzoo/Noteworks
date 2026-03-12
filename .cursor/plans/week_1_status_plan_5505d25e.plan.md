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


| Item                              | Status | Evidence                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                     |
| --------------------------------- | ------ | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Supabase project / local setup    | Done   | [config.toml](packages/supabase/supabase/config.toml) with API, DB, Auth, Storage, Realtime; PostgreSQL 15                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                   |
| Git repo + branching              | Done   | Repo exists; doc mentions main/develop/feature (assumed in use)                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                              |
| Supabase CLI + migration workflow | Done   | Root [package.json](package.json): `db:start`, `db:stop`, `db:reset`, `db:migrate`, `types:generate`; [packages/supabase](packages/supabase) has `migrate:new`, `migrate:up`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                 |
| Version-controlled migrations     | Done   | Six migrations: [20260201155932_initial_schema.sql](packages/supabase/supabase/migrations/20260201155932_initial_schema.sql), [20260201160000_enable_vault.sql](packages/supabase/supabase/migrations/20260201160000_enable_vault.sql), [20260203100000_enable_rls_users.sql](packages/supabase/supabase/migrations/20260203100000_enable_rls_users.sql), [20260203100001_schools_courses.sql](packages/supabase/supabase/migrations/20260203100001_schools_courses.sql), [20260203100002_courses_enrollments_notes.sql](packages/supabase/supabase/migrations/20260203100002_courses_enrollments_notes.sql), [20260203100003_enable_rls_rest.sql](packages/supabase/supabase/migrations/20260203100003_enable_rls_rest.sql) |
| CI/CD (schema + types validation) | Done   | [.github/workflows/sync-types.yml](.github/workflows/sync-types.yml): Supabase start, gen types, verify shared-types build on PR/push for `packages/supabase/**`, `packages/shared-types/**`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                 |
| Supabase Vault (secrets)          | Done   | [20260201160000_enable_vault.sql](packages/supabase/supabase/migrations/20260201160000_enable_vault.sql) enables Vault extension where available (cloud)                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                     |
| Shared TypeScript types           | Done   | [packages/shared-types](packages/shared-types): [database.types.ts](packages/shared-types/database.types.ts) (placeholder aligned to current schema), [api.types.ts](packages/shared-types/api.types.ts), [models.ts](packages/shared-types/models.ts)                                                                                                                                                                                                                                                                                                                                                                                                                                                                       |


### Days 3–4: Core schema (done except optional credits)


| Item                | Status  | Evidence                                                                                                                                                                                                                                                                                                                                                |
| ------------------- | ------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `users` table       | Partial | Exists with `id`, `email`, `name`, `created_at`, `updated_at` and `REFERENCES auth.users`. **Missing:** `credits` (integer) per plan — add in a migration if needed.                                                                                                                                                                                    |
| `schools` table     | Done    | [20260203100001_schools_courses.sql](packages/supabase/supabase/migrations/20260203100001_schools_courses.sql): `id`, `name`, `location`, `image`, `created_at`, `updated_at`                                                                                                                                                                           |
| `courses` table     | Done    | Same migration: `id`, `name`, `code`, `description`, `image`, `created_at`, `updated_at`; [20260203100002](packages/supabase/supabase/migrations/20260203100002_courses_enrollments_notes.sql) adds `code`/`image` if not present                                                                                                                       |
| User–course linkage | Done    | [school_enrollments](packages/supabase/supabase/migrations/20260203100001_schools_courses.sql) (school_id, user_id) and [course_enrollments](packages/supabase/supabase/migrations/20260203100002_courses_enrollments_notes.sql) (course_id, user_id, enrolled_at). **Note:** Plan’s `user_courses` year/role not yet columns; can add later if needed. |


### Day 5: Authentication (RLS done; onboarding flow pending)


| Item                                    | Status               | Evidence                                                                                                                                                                                                                         |
| --------------------------------------- | -------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Apple OAuth config (dashboard/local)    | Configured in config | [config.toml](packages/supabase/supabase/config.toml) has `[auth.external.apple]` with `client_id = "env(APPLE_CLIENT_ID)"`, `secret = "env(APPLE_SECRET)"`                                                                      |
| Google OAuth config                     | Configured in config | Same file has `[auth.external.google]` with env-based client_id/secret                                                                                                                                                           |
| RLS on `users`                          | Done                 | [20260203100000_enable_rls_users.sql](packages/supabase/supabase/migrations/20260203100000_enable_rls_users.sql): SELECT/UPDATE/INSERT own row                                                                                   |
| RLS on schools, courses, enrollments    | Done                 | [20260203100003_enable_rls_rest.sql](packages/supabase/supabase/migrations/20260203100003_enable_rls_rest.sql): read for schools/courses/school_courses; own-row CRUD for school_enrollments, course_enrollments; notes policies |
| Onboarding flow (school, courses, year) | Not done             | No backend implementation (client can use enrollments tables via RLS; no dedicated onboarding API)                                                                                                                               |
| Session / token refresh                 | Not done             | Plan item; typically client + Supabase Auth; no explicit backend work found                                                                                                                                                      |


---

## What you still need to do

### 1. Environment and secrets (Days 1–2)

- **Supabase Vault / env for OAuth:** Plan calls for “environment variables and secrets management using Supabase Vault.” Config already uses `env(APPLE_CLIENT_ID)`, etc.; you still need to:
  - Document where to set these (e.g. `.env` for local, Supabase dashboard or Vault for hosted).
  - Optionally add a small “Secrets & env” section to the repo or backend doc (what to set for Apple/Google, no values committed).
- **Production + staging:** Plan mentions “production + staging environments.” Confirm you have (or will create) two Supabase projects and document which env vars go where.

### 2. Core database schema (Days 3–4) — mostly done

- **Optional:** Add column `credits INTEGER` to `public.users` (default 0 or NOT NULL) in a new migration if required by product. All other Week 1 schema is in place: `schools`, `courses`, `school_courses`, `school_enrollments`, `course_enrollments` (and `notes` from Week 2 scope).
- After any schema change, run `pnpm types:generate` and commit updated [database.types.ts](packages/shared-types/database.types.ts) or rely on CI.

### 3. Row Level Security — RLS (Day 5) — done

- RLS is enabled on `public.users` with read/update/insert own row ([20260203100000_enable_rls_users.sql](packages/supabase/supabase/migrations/20260203100000_enable_rls_users.sql)).
- RLS is enabled on `schools`, `courses`, `school_courses`, `school_enrollments`, `course_enrollments`, `notes` with appropriate policies ([20260203100003_enable_rls_rest.sql](packages/supabase/supabase/migrations/20260203100003_enable_rls_rest.sql)).

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
2. **Optional schema:** Add `credits` to `users` in a migration if needed; run `pnpm types:generate`. (Core schema and RLS are already in place.)
3. **Onboarding:** Implement or document the “school, courses, year” flow (client can use `school_enrollments`/`course_enrollments` via RLS; add Edge Function or doc as needed).
4. **Verification:** Test Apple/Google sign-in and onboarding on iOS; confirm RLS by testing as different users.

---

## Week 1 deliverables checklist (from doc)


| Deliverable                                                | Status                                                                                                                                   |
| ---------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------- |
| Database Schema v1.0 (core tables, relationships, indexes) | Nearly complete — users, schools, courses, school_courses, school_enrollments, course_enrollments in place; optional: `credits` on users |
| Authentication (Apple + Google OAuth end-to-end)           | Config ready; env/Vault and iOS testing pending                                                                                          |
| RLS policies (user data access control)                    | Done — users and all core tables have RLS and policies                                                                                   |
| Migration scripts (version-controlled)                     | Done — six migrations including Vault and RLS                                                                                            |
| Development environment (staging + production ready)       | Local ready; staging/prod Supabase projects to confirm/document                                                                          |


Once secrets/env are documented, optional `credits` is added if needed, and onboarding flow is implemented and tested, you can mark Week 1 complete and move on to Week 2 (Notes & Storage).