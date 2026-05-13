# Test Edge Functions on Hosted Supabase (curl)

Use these curl commands to test the edge functions against your **hosted** project.  
Base URL: `https://app.noteworks.studio`

**Set these before running** (from Dashboard → Project Settings → API, and from sign-in response):

- `ANON_KEY` — Project API key (anon, public)
- `ACCESS_TOKEN` — JWT from sign-in (step 1)
- `USER_ID` — `user.id` from sign-in (step 1)
- `COURSE_ID` — any course UUID (e.g. from step 2 or seed data)
- `NOTE_ID` — from create-note response (step 3)

---

## 0a. Get user profile

After sign-in, fetch the current user's profile to check if onboarding is complete.

```bash
curl "https://app.noteworks.studio/functions/v1/get-user-profile" \
  -H "Authorization: Bearer YOUR_ACCESS_TOKEN" \
  -H "apikey: YOUR_ANON_KEY"
```

If `onboarding_completed_at` is `null`, the user hasn't completed onboarding yet.

---

## 0b. Get schools (for onboarding picker)

```bash
curl "https://app.noteworks.studio/functions/v1/get-schools?page=1&pageSize=20" \
  -H "Authorization: Bearer YOUR_ACCESS_TOKEN" \
  -H "apikey: YOUR_ANON_KEY"
```

Optional: `&search=MIT` to filter by name or location.

---

## 0c. Submit onboarding (school, graduation year, course codes)

After sign-in, call this once to complete onboarding. It updates the user profile and creates school + course enrollments from the course codes you send.

```bash
curl -X POST "https://app.noteworks.studio/functions/v1/submit-onboarding" \
  -H "Authorization: Bearer YOUR_ACCESS_TOKEN" \
  -H "apikey: YOUR_ANON_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "Your Name",
    "year_of_graduation": 2028,
    "school_affiliation": "Your University",
    "school_email": "you@school.edu",
    "course_codes": ["CS101", "MATH201"]
  }'
```

- **name**, **year_of_graduation** (integer, e.g. 2028), **school_affiliation**, **school_email** are required.
- **course_codes** is an array of strings (course codes from your school). Can be empty `[]`. Each code is matched to `courses.code` and enrollments are created for matches.

---

## 1. Sign in (get token and user id)

```bash
curl -X POST "https://app.noteworks.studio/auth/v1/token?grant_type=password" \
  -H "apikey: YOUR_ANON_KEY" \
  -H "Content-Type: application/json" \
  -d '{"email": "your-user@example.com", "password": "your-password"}'
```

From the response, copy `access_token` → `ACCESS_TOKEN` and `user.id` → `USER_ID`.

---

## 2. Get courses (list)

```bash
curl "https://app.noteworks.studio/functions/v1/get-courses?page=1&pageSize=10" \
  -H "Authorization: Bearer YOUR_ACCESS_TOKEN" \
  -H "apikey: YOUR_ANON_KEY"
```

Optional: `&search=math` to filter by name/code. Copy one `id` as `COURSE_ID` if needed.

---

## 2b. Get courses by school

```bash
curl "https://app.noteworks.studio/functions/v1/get-school-courses?school_id=YOUR_SCHOOL_ID&page=1&pageSize=10" \
  -H "Authorization: Bearer YOUR_ACCESS_TOKEN" \
  -H "apikey: YOUR_ANON_KEY"
```

Optional: `&search=math` to filter by name/code within that school's courses.

---

## 3. Create a note

```bash
curl -X POST "https://app.noteworks.studio/functions/v1/create-note" \
  -H "Authorization: Bearer YOUR_ACCESS_TOKEN" \
  -H "apikey: YOUR_ANON_KEY" \
  -H "Content-Type: application/json" \
  -d '{"title": "Test note for PDF", "course_id": "YOUR_COURSE_ID"}'
```

Copy the returned `id` as `NOTE_ID` for the next steps. Example course ID from seed: `c0000000-0000-0000-0000-000000000001`.

---

## 4. Get notes (list, optional course filter)

```bash
curl "https://app.noteworks.studio/functions/v1/get-notes?course_id=YOUR_COURSE_ID&page=1&pageSize=10" \
  -H "Authorization: Bearer YOUR_ACCESS_TOKEN" \
  -H "apikey: YOUR_ANON_KEY"
```

Omit `course_id` to list all notes the user can see.

---

## 5. Get single note by ID

```bash
curl "https://app.noteworks.studio/functions/v1/get-notes?id=YOUR_NOTE_ID" \
  -H "Authorization: Bearer YOUR_ACCESS_TOKEN" \
  -H "apikey: YOUR_ANON_KEY"
```

---

## 6. Upload PDF to note

Send the PDF as binary body. Replace `path/to/file.pdf` with a real file.

```bash
curl -X POST "https://app.noteworks.studio/functions/v1/upload-note-pdf?note_id=YOUR_NOTE_ID&filename=mynotes.pdf" \
  -H "Authorization: Bearer YOUR_ACCESS_TOKEN" \
  -H "apikey: YOUR_ANON_KEY" \
  -H "Content-Type: application/pdf" \
  --data-binary @path/to/file.pdf
```

---

## 7. Get signed PDF download URL

```bash
curl "https://app.noteworks.studio/functions/v1/get-note-pdf-url?note_id=YOUR_NOTE_ID" \
  -H "Authorization: Bearer YOUR_ACCESS_TOKEN" \
  -H "apikey: YOUR_ANON_KEY"
```

Optional: `&expires_in=3600` (seconds, default 3600, max 86400).

---

## 8. Update note (title and/or metadata)

```bash
curl -X PATCH "https://app.noteworks.studio/functions/v1/update-note" \
  -H "Authorization: Bearer YOUR_ACCESS_TOKEN" \
  -H "apikey: YOUR_ANON_KEY" \
  -H "Content-Type: application/json" \
  -d '{"note_id": "YOUR_NOTE_ID", "title": "Updated note title"}'
```

To update only metadata:

```bash
curl -X PATCH "https://app.noteworks.studio/functions/v1/update-note" \
  -H "Authorization: Bearer YOUR_ACCESS_TOKEN" \
  -H "apikey: YOUR_ANON_KEY" \
  -H "Content-Type: application/json" \
  -d '{"note_id": "YOUR_NOTE_ID", "metadata": {"custom_key": "custom_value"}}'
```

---

## 9. Delete note (and its PDF in storage)

```bash
curl -X DELETE "https://app.noteworks.studio/functions/v1/delete-note?id=YOUR_NOTE_ID" \
  -H "Authorization: Bearer YOUR_ACCESS_TOKEN" \
  -H "apikey: YOUR_ANON_KEY"
```

---

## One-liner checklist (replace placeholders)

| Step | Command |
|------|---------|
| Sign in | `curl -X POST "https://app.noteworks.studio/auth/v1/token?grant_type=password" -H "apikey: ANON_KEY" -H "Content-Type: application/json" -d '{"email":"YOU@example.com","password":"PASS"}'` |
| Get profile | `curl "https://app.noteworks.studio/functions/v1/get-user-profile" -H "Authorization: Bearer TOKEN" -H "apikey: ANON_KEY"` |
| Get schools | `curl "https://app.noteworks.studio/functions/v1/get-schools?page=1&pageSize=20" -H "Authorization: Bearer TOKEN" -H "apikey: ANON_KEY"` |
| Submit onboarding | `curl -X POST "https://app.noteworks.studio/functions/v1/submit-onboarding" -H "Authorization: Bearer TOKEN" -H "apikey: ANON_KEY" -H "Content-Type: application/json" -d '{"name":"Name","year_of_graduation":2028,"school_affiliation":"School","school_email":"you@school.edu","course_codes":["CS101","MATH201"]}'` |
| Get courses | `curl "https://app.noteworks.studio/functions/v1/get-courses?page=1&pageSize=10" -H "Authorization: Bearer TOKEN" -H "apikey: ANON_KEY"` |
| Get school courses | `curl "https://app.noteworks.studio/functions/v1/get-school-courses?school_id=SCHOOL_ID&page=1&pageSize=10" -H "Authorization: Bearer TOKEN" -H "apikey: ANON_KEY"` |
| Create note | `curl -X POST "https://app.noteworks.studio/functions/v1/create-note" -H "Authorization: Bearer TOKEN" -H "apikey: ANON_KEY" -H "Content-Type: application/json" -d '{"title":"Test","course_id":"COURSE_UUID"}'` |
| Get notes | `curl "https://app.noteworks.studio/functions/v1/get-notes?id=NOTE_ID" -H "Authorization: Bearer TOKEN" -H "apikey: ANON_KEY"` |
| Upload PDF | `curl -X POST "https://app.noteworks.studio/functions/v1/upload-note-pdf?note_id=NOTE_ID&filename=f.pdf" -H "Authorization: Bearer TOKEN" -H "apikey: ANON_KEY" -H "Content-Type: application/pdf" --data-binary @file.pdf` |
| Get PDF URL | `curl "https://app.noteworks.studio/functions/v1/get-note-pdf-url?note_id=NOTE_ID" -H "Authorization: Bearer TOKEN" -H "apikey: ANON_KEY"` |
| Update note | `curl -X PATCH "https://app.noteworks.studio/functions/v1/update-note" -H "Authorization: Bearer TOKEN" -H "apikey: ANON_KEY" -H "Content-Type: application/json" -d '{"note_id":"NOTE_ID","title":"New title"}'` |
| Delete note | `curl -X DELETE "https://app.noteworks.studio/functions/v1/delete-note?id=NOTE_ID" -H "Authorization: Bearer TOKEN" -H "apikey: ANON_KEY"` |

Ensure edge functions are deployed: `cd packages/supabase && npx supabase functions deploy`.
