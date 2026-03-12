# User Onboarding Plan

**Purpose:** Collect required user information after first sign-in via a single onboarding step. 
**Reference:** Carried-over item from [Week 1 Status](week_1_status_plan_5505d25e.plan.md) and [Week 2 Plan](week_2_step_by_step_plan.md) — “User onboarding (school, courses, year)”.

---

## 1. Onboarding fields

| Field               | Description                    | Input type | Required |
|---------------------|--------------------------------|------------|----------|
| **User's name**     | Display name                   | Text       | Yes      |
| **Year of study**   | Academic year (see options below) | **Dropdown** | Yes   |
| **School affiliation** | School name or institution  | Text       | Yes      |
| **School email**    | Institutional email address    | Text       | Yes      |

**Year of study dropdown options** (format: Freshman / Year 1, etc.) — store the selected label as text:

- Freshman (Year 1)
- Sophomore (Year 2)
- Junior (Year 3)
- Senior (Year 4)
- **Other** — when selected, optionally show a text field for "Other (please specify)" and store that value in `year_of_study`; otherwise store `"Other"`.

Optionally extend with Year 5, Graduate, etc. if needed. Backend stores the selected string in `year_of_study` (TEXT).

---

## 2. When onboarding runs

- **Trigger:** After first successful sign-in (Apple/Google OAuth or email), when the app detects that the user has not completed onboarding.
- **Completion flag:** Stored per user (e.g. `onboarding_completed_at` on `public.users` or a dedicated profile table) so the app can skip onboarding on subsequent launches.
- **Blocking:** User cannot access main app until onboarding is completed (optional product decision; plan assumes “required before home screen”).

---

## 3. Data model and storage

### 3.1 Current schema

- **`public.users`** ([20260201155932_initial_schema.sql](../../packages/supabase/supabase/migrations/20260201155932_initial_schema.sql)): `id`, `email`, `name`, `created_at`, `updated_at`.
- **`public.school_enrollments`**: `school_id`, `user_id`, `enrolled_at` — links user to a **school row** (UUID). No free-text “school affiliation” or “year of study” today.

### 3.2 Recommended approach

Store onboarding data on the user record so a single update completes onboarding:

| Data item           | Storage location        | Notes |
|---------------------|-------------------------|--------|
| User's name         | `public.users.name`     | Already exists. |
| Year of study       | New column on `users`   | e.g. `year_of_study TEXT`. |
| School affiliation  | New column on `users`   | e.g. `school_affiliation TEXT` (free text). |
| School email        | New column on `users`   | e.g. `school_email TEXT` (separate from auth `email`). |
| Onboarding completed| New column on `users`   | e.g. `onboarding_completed_at TIMESTAMPTZ` (NULL = not done). |

**Migration (example):**

```sql
ALTER TABLE public.users
  ADD COLUMN IF NOT EXISTS year_of_study TEXT,
  ADD COLUMN IF NOT EXISTS school_affiliation TEXT,
  ADD COLUMN IF NOT EXISTS school_email TEXT,
  ADD COLUMN IF NOT EXISTS onboarding_completed_at TIMESTAMPTZ;
```

- Optional: later add a link from `users` to `schools` (e.g. `school_id UUID REFERENCES schools(id)`) if you want to tie “school affiliation” to the existing `schools` table; for this plan we keep it text-only.

---

## 4. Backend

### 4.1 API contract

- **Check onboarding status:**  
  - Client reads `public.users` (RLS: own row only) and checks `onboarding_completed_at IS NULL`.
- **Submit onboarding:**  
  - Single update to `public.users`: set `name`, `year_of_study`, `school_affiliation`, `school_email`, and `onboarding_completed_at = NOW()`.
  - Use Supabase PostgREST (client with RLS) or an Edge Function that:
    - Verifies the authenticated user.
    - Updates only that user’s row.
    - Sets `updated_at = NOW()`.

### 4.2 RLS

- Existing RLS on `users` should allow:
  - **SELECT** own row (so client can see onboarding status and prefill name/email if needed).
  - **UPDATE** own row (so client can submit the four text fields and `onboarding_completed_at`).
- No new policies required if “users can update own row” is already in place; otherwise add an UPDATE policy for `auth.uid() = id`.

### 4.3 Validation (backend)

- **Name:** Non-empty string; max length (e.g. 255).
- **Year of study:** One of the allowed dropdown values (e.g. "Freshman (Year 1)" … "Senior (Year 4)", "Other", or custom text when Other is selected); reject unknown values if validating server-side.
- **School affiliation:** Non-empty string; max length (e.g. 255).
- **School email:** Non-empty string; format check (e.g. valid email); max length (e.g. 255). Optionally enforce domain rules later (e.g. must match school domain).

---

## 5. Client (iOS / app)

### 5.1 Flow

1. User signs in (OAuth or email).
2. App fetches `public.users` for current user.
3. If `onboarding_completed_at` is NULL → show **Onboarding screen**.
4. Onboarding screen: User's name (text), **Year of study (dropdown)**, School affiliation (text), School email (text).
5. Submit: PATCH `public.users` with the four values + `onboarding_completed_at = NOW()`.
6. On success: set completion flag locally (or refetch user), then navigate to main app (e.g. home).

### 5.2 UI

- Single screen: three text fields (name, school affiliation, school email), one **dropdown** for Year of study (options: Freshman (Year 1), Sophomore (Year 2), Junior (Year 3), Senior (Year 4), Other), and a “Continue” or “Finish” button.
- Optional: prefill **User's name** or **School email** from auth (e.g. from OAuth identity or `users.email`) if available.
- Optional: basic client-side validation (non-empty, email format for school email) before submit.
- Accessibility: labels, placeholders, and error messages for each field.

### 5.3 Edge cases

- **Network failure on submit:** Show error; allow retry without losing input (keep form state).
- **User closes app mid-onboarding:** On next launch, still show onboarding until `onboarding_completed_at` is set.
- **Edit later:** If product wants “edit profile” later, reuse same fields from `users` in a profile/settings screen.

---

## 6. Implementation checklist

### Schema and backend

- [ ] Add migration: `year_of_study`, `school_affiliation`, `school_email`, `onboarding_completed_at` to `public.users`.
- [ ] Run migration locally; run `pnpm types:generate` (or equivalent) and commit updated types.
- [ ] Confirm RLS: users can SELECT and UPDATE own row on `users`.
- [ ] (Optional) Add Edge Function for onboarding submit with validation; otherwise use direct PostgREST from client.

### Shared types

- [ ] Add TypeScript types for new `users` columns and (if used) an `OnboardingSubmit` request type in `packages/shared-types`.

### Client

- [ ] After sign-in, check `onboarding_completed_at`; if NULL, show onboarding screen.
- [ ] Implement onboarding screen: three text fields (name, school affiliation, school email), one dropdown (year of study with options Freshman (Year 1) … Senior (Year 4), Other; optional text field when Other is selected), and submit.
- [ ] On success, set `onboarding_completed_at` and navigate to main app.
- [ ] Handle errors and retry; optional prefill from auth.

### Documentation

- [ ] Document onboarding flow and API (e.g. in Monorepo_Documentation or backend doc).
- [ ] Update Week 1 / Week 2 plan status to “User onboarding (name, year, school, school email)” when done.

---

## 7. Testing with Postman (or similar)

You can test the onboarding API with **Postman**, **Insomnia**, or **curl**. Supabase exposes PostgREST, so you call the `users` table over REST. RLS allows only the **authenticated user** to read/update their own row, so you need a valid JWT first.

### Prerequisites

- **Supabase project URL** and **anon key** (from Supabase dashboard → Project Settings → API).
- The onboarding columns exist on `public.users` (run the migration from section 3.2 first).

### Step 1: Get an access token (JWT)

Sign in with Supabase Auth so you get a JWT. Use **email + password** (or magic link) for the user whose profile you want to update.

**Postman — Sign in (get JWT):**

- **Method:** `POST`
- **URL:** `https://<YOUR_PROJECT_REF>.supabase.co/auth/v1/token?grant_type=password`
- **Headers:**
  - `Content-Type: application/json`
  - `apikey: <YOUR_ANON_KEY>`
- **Body (raw JSON):**
  ```json
  {
    "email": "test@example.com",
    "password": "your-test-password"
  }
  ```
- Send the request. From the response, copy `access_token` (this is your JWT).

(If you use magic link or OAuth, use the Supabase Auth endpoints that return `access_token` and copy it the same way.)

### Step 2: Check onboarding status (GET own user row)

- **Method:** `GET`
- **URL:** `https://<YOUR_PROJECT_REF>.supabase.co/rest/v1/users?id=eq.<USER_UUID>`
  - Replace `<USER_UUID>` with the signed-in user's ID (same as `auth.users.id`; you can get it from the sign-in response as `user.id`).
- **Headers:**
  - `apikey: <YOUR_ANON_KEY>`
  - `Authorization: Bearer <ACCESS_TOKEN>`
  - `Content-Type: application/json`
  - `Prefer: return=representation` (optional; returns the row in the response)
- If `onboarding_completed_at` is `null`, the user has not completed onboarding.

### Step 3a: Submit onboarding via Edge Function (recommended)

Use the **submit-onboarding** Edge Function for server-side validation.

- **Method:** `POST`
- **URL:** `https://<YOUR_PROJECT_REF>.supabase.co/functions/v1/submit-onboarding`  
  (Local: `http://127.0.0.1:54321/functions/v1/submit-onboarding` when running `supabase functions serve`.)
- **Headers:**
  - `Authorization: Bearer <ACCESS_TOKEN>`
  - `Content-Type: application/json`
- **Body (raw JSON):**
  ```json
  {
    "name": "Jane Doe",
    "year_of_study": "Sophomore (Year 2)",
    "school_affiliation": "State University",
    "school_email": "jane.doe@university.edu"
  }
  ```
  - Do **not** send `onboarding_completed_at`; the function sets it automatically.
- Send the request. Expect **200** with the updated user row in the body, or **400** with `{ "error": "Validation failed", "errors": { "field": "message" } }`, or **401** if the token is missing or invalid.

### Step 3b: Submit onboarding (PATCH own user row via PostgREST)

Alternative: update the row directly via PostgREST (no server-side validation).

- **Method:** `PATCH`
- **URL:** `https://<YOUR_PROJECT_REF>.supabase.co/rest/v1/users?id=eq.<USER_UUID>`
  - Use the **same** `<USER_UUID>` as the signed-in user (RLS only allows updating your own row).
- **Headers:**
  - `apikey: <YOUR_ANON_KEY>`
  - `Authorization: Bearer <ACCESS_TOKEN>`
  - `Content-Type: application/json`
  - `Prefer: return=representation`
- **Body (raw JSON):**
  ```json
  {
    "name": "Jane Doe",
    "year_of_study": "Sophomore (Year 2)",
    "school_affiliation": "State University",
    "school_email": "jane.doe@university.edu",
    "onboarding_completed_at": "2025-02-15T12:00:00Z"
  }
  ```
  - For `onboarding_completed_at` you can use any ISO 8601 timestamp, or rely on a DB default/trigger if you add one; otherwise send current time in UTC.
- Send the request. You should get back the updated row (or 204 No Content). A 403 or empty result usually means the JWT is missing, wrong user id, or RLS blocked the update.

### Step 4: Verify (GET again)

- Repeat **Step 2**. You should see `name`, `year_of_study`, `school_affiliation`, `school_email`, and `onboarding_completed_at` populated.

### Tips

- **Postman:** Save the JWT as an environment variable (e.g. `supabase_access_token`) and use `Bearer {{supabase_access_token}}` in the Authorization header for GET/PATCH and for the submit-onboarding Edge Function.
- **Local Supabase:** If you use `supabase start`, replace the host with your local URL (e.g. `http://127.0.0.1:54321`) and use the local anon key from `supabase status`. For the Edge Function, run `supabase functions serve` (or `pnpm functions:serve` from `packages/supabase`) and POST to `http://127.0.0.1:54321/functions/v1/submit-onboarding`.
- **Creating a test user:** In Supabase dashboard → Authentication → Users, add a user with email/password, then use that email/password in Step 1.

---

## 8. Summary

| Item | Decision |
|------|----------|
| **Fields** | User's name (text), Year of study (dropdown: Freshman/Year 1 … Senior/Year 4, Other), School affiliation (text), School email (text). |
| **Storage** | `public.users`: use existing `name`; add `year_of_study` (TEXT, selected dropdown value), `school_affiliation`, `school_email`, `onboarding_completed_at`. |
| **When** | After first sign-in until `onboarding_completed_at` is set. |
| **API** | Read/update own `users` row via PostgREST (or Edge Function). |
| **Client** | One screen: three text fields + one year dropdown, submit then proceed to main app. |

This plan keeps onboarding simple and aligned with your existing Supabase schema and RLS.
