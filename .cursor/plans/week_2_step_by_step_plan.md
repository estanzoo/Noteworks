# Week 2: Notes Core & File Storage — Step-by-Step Plan

**Reference:** [Noteworks Backend 6-Week Plan](docs/backend/Noteworks_Backend_6Week_Plan.md) (Week 2)  
**Prerequisite status:** [Week 1 Status Plan](.cursor/plans/week_1_status_plan_5505d25e.plan.md)

---

## Part A: Incomplete Items Carried Over from Week 1

These items were not finished in Week 1 (in part due to no Apple Developer account yet). They do not block Week 2 backend work but should be tracked and completed when possible.

### 1. Authentication & OAuth (blocked by Apple Developer account)

| Item | Status | Action when unblocked |
|------|--------|------------------------|
| **Apple OAuth end-to-end** | Config in place; cannot test | Once Apple Dev account exists: add credentials to Supabase (env/Vault), set redirect URIs, test on iOS simulator/device |
| **Google OAuth verification** | Config in place | Verify redirect URIs and credentials in Supabase dashboard; test sign-in |
| **Session management & token refresh** | Not explicitly implemented | Document that Supabase client SDK on iOS handles this; add any custom middleware later if needed |

### 2. Environment & secrets

| Item | Status | Action |
|------|--------|--------|
| **OAuth secrets documentation** | Not done | Document where to set `APPLE_CLIENT_ID`, `APPLE_SECRET`, Google client_id/secret (e.g. `.env` for local, Supabase dashboard/Vault for hosted). Do not commit values. |
| **Production + staging** | Not confirmed | Confirm two Supabase projects (staging + production) and document which env vars go where |

### 3. Core schema (optional)

| Item | Status | Action |
|------|--------|--------|
| **`credits` on `users`** | Not in schema | Add migration `ALTER TABLE public.users ADD COLUMN credits INTEGER NOT NULL DEFAULT 0` (and optionally `CHECK (credits >= 0)`) when credit economy is needed; run `pnpm types:generate` |

### 4. Onboarding & product flow

| Item | Status | Action |
|------|--------|--------|
| **User onboarding (school, courses, year)** | Not implemented | Implement backend: e.g. Edge Function or direct API that creates/updates school_enrollments + course_enrollments; client calls after first sign-in. Plan’s `user_courses` year/role can be added as columns later. |
| **Testing auth flows on iOS** | Pending | Manual/QA once Apple/Google credentials are available |

### 5. Optional improvements (Week 1)

| Item | Status | Action |
|------|--------|--------|
| **Migration script** | `scripts/generate-migration.sh` empty | Add one-liner to run `supabase migration new` from repo root |
| **Seed data** | `packages/supabase/supabase/seed.sql` stub | Add minimal seed (e.g. one school, one course) for testing |

---

## Part B: Week 2 Step-by-Step Plan

### Phase 1: Notes data model (Days 1–2)

#### Step 1.1 — Extend `notes` table for Week 2

- [ ] Add `deleted_at TIMESTAMPTZ` to `public.notes` (nullable; NULL = not deleted) for soft delete.
- [ ] Add composite indexes per plan:
  - `(user_id, created_at)` — for “my notes by date”.
  - `(course_id, created_at)` — for “course notes by date”.
- [ ] Create migration; run locally; run `pnpm types:generate` and commit updated types.

#### Step 1.2 — Full-text search on notes

- [ ] Add `search_vector TSVECTOR` (or equivalent) column to `public.notes`.
- [ ] Create trigger to update `search_vector` on INSERT/UPDATE from `title` and from `metadata` (or content fields you store there).
- [ ] Create GIN index on `search_vector` for fast search.
- [ ] Migration + types regeneration.

#### Step 1.3 — `note_versions` table

- [ ] Create table:
  - `id UUID PRIMARY KEY DEFAULT gen_random_uuid()`
  - `note_id UUID NOT NULL REFERENCES public.notes(id) ON DELETE CASCADE`
  - `version_number INTEGER NOT NULL`
  - `content_url TEXT` (reference to storage or external URL)
  - `created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()`
- [ ] Add unique constraint or unique index on `(note_id, version_number)`.
- [ ] Add index on `(note_id, created_at)` for “latest version” queries.
- [ ] Enable RLS; add policies: same visibility as notes (e.g. note owner and course-enrolled users can read; only note owner can insert/update/delete).
- [ ] Migration + types regeneration.

#### Step 1.4 — Cascading and constraints

- [ ] Confirm foreign keys: `notes.user_id` → `users`, `notes.course_id` → `courses`; `note_versions.note_id` → `notes` with ON DELETE CASCADE.
- [ ] Ensure soft delete is respected in RLS (e.g. policies filter `deleted_at IS NULL` for default reads, or document that API layer filters).

---

### Phase 2: File storage (Days 3–4)

#### Step 2.1 — Storage buckets

- [ ] Create Supabase Storage buckets:
  - `notes-data` — PKDrawing binary and note content blobs.
  - `images` — images (photos, embedded images).
  - `materials` — course materials.
- [ ] Document bucket purpose and retention in repo or backend doc.

#### Step 2.2 — Bucket RLS policies

- [ ] Define RLS policies for each bucket so that:
  - Only authenticated users can read/write.
  - Access is scoped by ownership or course enrollment (e.g. users can read/write objects in paths that include their `user_id` or their enrolled `course_id`).
- [ ] Test: upload/list/delete as different users to verify isolation.

#### Step 2.3 — CORS for iOS

- [ ] Configure CORS for Storage so the iOS client can upload/download from allowed origins (e.g. app scheme or web URL if applicable).
- [ ] Document allowed origins in backend doc or config.

#### Step 2.4 — CDN / delivery (optional for MVP)

- [ ] If using Supabase CDN or custom domain, configure for `notes-data`, `images`, `materials` and document in deployment guide.

#### Step 2.5 — Image compression Edge Function

- [ ] Create Edge Function (e.g. `image-compress` or `process-image`):
  - Input: image file (e.g. from Storage or multipart upload).
  - Logic: resize to max 1920px (width or height), keep aspect ratio; optionally compress (e.g. JPEG quality).
  - Output: write result to `images` bucket (or return URL).
- [ ] Secure: validate auth, validate file type/size; use Supabase Vault for any keys if needed.
- [ ] Document: trigger (e.g. on upload to a staging path, or called explicitly by client after upload).

#### Step 2.6 — PKDrawing storage strategy

- [ ] Document strategy: store PKDrawing binary in `notes-data` bucket (e.g. path like `{user_id}/{note_id}/drawing.pkd` or per-version).
- [ ] Ensure RLS and `content_url` in `note_versions` align with this path scheme.
- [ ] If needed, add a small Edge Function to generate signed URLs for secure client access.

#### Step 2.7 — File cleanup for deleted notes

- [ ] Implement scheduled cleanup: when a note is soft-deleted (or hard-deleted), remove associated objects from `notes-data` and `images` (and optionally `note_versions` if hard delete).
- [ ] Options: Supabase cron + Edge Function, or pg_cron calling a function that marks/deletes blobs; or client-triggered cleanup with server validation. Document chosen approach.

---

### Phase 3: Real-time synchronization (Day 5)

#### Step 3.1 — Realtime on `notes`

- [ ] Enable Realtime replication for `public.notes` in Supabase (dashboard or config).
- [ ] Ensure Realtime is allowed only for authenticated users and that RLS applies to the Realtime stream (users see only notes they’re allowed to see).

#### Step 3.2 — WebSocket auth and authorization

- [ ] Confirm Supabase client uses JWT for Realtime; document that authorization is enforced by RLS on the replicated table.
- [ ] If using custom channels, implement channel-level auth (e.g. user can subscribe only to channels for their user_id or course_id).

#### Step 3.3 — Conflict resolution

- [ ] Document and implement strategy: e.g. last-write-wins using `updated_at` (and optionally version numbers for note_versions).
- [ ] Ensure all note updates set `updated_at = NOW()` (trigger or application layer).

#### Step 3.4 — Real-time listeners and testing

- [ ] Add or document real-time listeners for note changes (create, update, delete) for use by the iOS client.
- [ ] Test multi-device: create/update/delete on one client, verify others receive events.
- [ ] Test offline-to-online: queue changes locally, then sync when online; verify no duplicate rows and conflict behavior.

---

### Phase 4: Notes CRUD API and documentation

#### Step 4.1 — Notes CRUD

- [ ] Implement or expose CRUD with validation:
  - Create: validate `user_id`, `course_id`, `title`; set `created_at`/`updated_at`; optionally create first `note_versions` row and upload to Storage.
  - Read: list (with filters by user, course, date; respect soft delete); get by id.
  - Update: update title/metadata and `updated_at`; optionally create new `note_versions` row and new `content_url`.
  - Delete: soft delete (set `deleted_at`) or hard delete; trigger cleanup for Storage (see Step 2.7).
- [ ] Use Supabase PostgREST (direct from client with RLS) or Edge Functions; document chosen approach.

#### Step 4.2 — API documentation

- [ ] Document endpoints (and any Edge Functions) with:
  - Method and path.
  - Request body/query params.
  - Response shape and status codes.
  - Example requests/responses (e.g. in OpenAPI or Markdown).
- [ ] Include: list notes, get note, create note, update note, delete note; and any search endpoint (search can be deepened in Week 3).

---

## Week 2 deliverables checklist

| Deliverable | Steps |
|-------------|--------|
| **Notes CRUD API** | Phase 1 (schema + RLS), Phase 4.1 |
| **File storage (RLS, CDN)** | Phase 2.1–2.4 |
| **Image compression** | Phase 2.5 |
| **Real-time sync** | Phase 3 |
| **API documentation** | Phase 4.2 |

---

## Suggested order of work (summary)

1. **Carried over (optional, non-blocking):** Document OAuth env/secrets; add `credits` to `users` if needed; optionally fill migration script and seed.
2. **Phase 1:** Notes schema (deleted_at, indexes, tsvector, note_versions, RLS).
3. **Phase 2:** Buckets, RLS, CORS, image compression Edge Function, PKDrawing strategy, cleanup.
4. **Phase 3:** Realtime on notes, auth, conflict resolution, listeners, multi-device and offline tests.
5. **Phase 4:** CRUD validation and API documentation.

Once Phase 1–4 are done, Week 2 is complete. Incomplete Week 1 items (especially Apple OAuth and onboarding) can be completed in parallel or in a dedicated catch-up window once the Apple Developer account is available.
