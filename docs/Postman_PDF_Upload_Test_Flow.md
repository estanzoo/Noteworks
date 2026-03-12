# Postman: Test PDF Upload Flow

Use this flow to test uploading a PDF for a user: sign in, create a note, upload the PDF to the `notes-pdfs` bucket, then update the note’s metadata.

**Prerequisites:** A Supabase project (hosted or local), a test user (email/password), and at least one course row. Use the same **Project URL** and **anon key** everywhere.

---

## 1. Sign in (get JWT and user id)

- **Method:** `POST`
- **URL:** `{{SUPABASE_URL}}/auth/v1/token?grant_type=password`
  - Example: `https://YOUR_PROJECT_REF.supabase.co/auth/v1/token?grant_type=password`
  - Local: `http://127.0.0.1:54321/auth/v1/token?grant_type=password`
- **Headers:**
  - `Content-Type: application/json`
  - `apikey: {{SUPABASE_ANON_KEY}}`
- **Body (raw JSON):**
  ```json
  {
    "email": "test@example.com",
    "password": "your-test-password"
  }
  ```
- **Save from response:** `access_token` (JWT) and `user.id` (UUID). Use them as `{{ACCESS_TOKEN}}` and `{{USER_ID}}` in the next steps.

---

## 2. Get a course id (if you don’t have one)

- **Method:** `GET`
- **URL:** `{{SUPABASE_URL}}/rest/v1/courses?select=id,name&limit=1`
- **Headers:**
  - `apikey: {{SUPABASE_ANON_KEY}}`
  - `Authorization: Bearer {{ACCESS_TOKEN}}`
- **Save from response:** one `id` (UUID) as `{{COURSE_ID}}`. If the list is empty, create a course first (e.g. via Table Editor in Supabase Studio or a separate POST to `rest/v1/courses`).

---

## 3. Create a note

- **Method:** `POST`
- **URL:** `{{SUPABASE_URL}}/rest/v1/notes`
- **Headers:**
  - `Content-Type: application/json`
  - `apikey: {{SUPABASE_ANON_KEY}}`
  - `Authorization: Bearer {{ACCESS_TOKEN}}`
  - `Prefer: return=representation`
- **Body (raw JSON):**
  ```json
  {
    "course_id": "{{COURSE_ID}}",
    "user_id": "{{USER_ID}}",
    "title": "Test note for PDF upload"
  }
  ```
- **Save from response:** the returned note’s `id` as `{{NOTE_ID}}`.

---

## 4. Upload the PDF to Storage

Path convention: `{user_id}/{note_id}.pdf`. The bucket is `notes-pdfs` and RLS allows only the owner to upload to their own folder.

- **Method:** `POST`
- **URL:** `{{SUPABASE_URL}}/storage/v1/object/notes-pdfs/{{USER_ID}}/{{NOTE_ID}}.pdf`
  - Example: `https://YOUR_PROJECT_REF.supabase.co/storage/v1/object/notes-pdfs/abc-123-uuid/def-456-note-uuid.pdf`
- **Headers:**
  - `apikey: {{SUPABASE_ANON_KEY}}`
  - `Authorization: Bearer {{ACCESS_TOKEN}}`
  - `Content-Type: application/pdf`
- **Body:** `binary` — in Postman, choose **Body → binary**, then **Select File** and pick a PDF (max 50 MB).
- **Success:** 200 with a JSON body containing a `Key` (storage path). If you get 403, the JWT or path is wrong (path must start with `{{USER_ID}}/`).

---

## 5. Update the note’s metadata with PDF info

- **Method:** `PATCH`
- **URL:** `{{SUPABASE_URL}}/rest/v1/notes?id=eq.{{NOTE_ID}}`
- **Headers:**
  - `Content-Type: application/json`
  - `apikey: {{SUPABASE_ANON_KEY}}`
  - `Authorization: Bearer {{ACCESS_TOKEN}}`
  - `Prefer: return=representation`
- **Body (raw JSON):**  
  Replace `USER_ID`, `NOTE_ID`, the filename, size, and timestamp with the values you used or got from step 4.
  ```json
  {
    "metadata": {
      "pdf_path": "{{USER_ID}}/{{NOTE_ID}}.pdf",
      "pdf_size_bytes": 2048576,
      "pdf_filename": "MyLectureNotes.pdf",
      "pdf_uploaded_at": "2026-02-16T12:00:00Z"
    }
  }
  ```
  - `pdf_size_bytes`: size in bytes of the file you uploaded (e.g. from Postman or your OS).
  - `pdf_uploaded_at`: any ISO 8601 timestamp (e.g. now in UTC).
- **Success:** 200 and the updated note row in the response.

---

## 6. Verify: get the note and download the PDF

**Get note (including metadata):**
- **Method:** `GET`
- **URL:** `{{SUPABASE_URL}}/rest/v1/notes?id=eq.{{NOTE_ID}}&select=id,title,metadata`
- **Headers:** `apikey`, `Authorization: Bearer {{ACCESS_TOKEN}}`
- You should see `metadata.pdf_path`, `metadata.pdf_filename`, etc.

**Get a signed download URL (optional):**  
Supabase Storage doesn’t expose a single REST endpoint that returns a signed URL; the JS client uses `createSignedUrl()`. In Postman you can:
- Call `GET {{SUPABASE_URL}}/storage/v1/object/notes-pdfs/{{USER_ID}}/{{NOTE_ID}}.pdf` with the same `apikey` and `Authorization: Bearer {{ACCESS_TOKEN}}` — if the bucket allows authenticated read, you may get the file directly; otherwise use the client SDK or an Edge Function that returns a signed URL.

---

## Postman variables (optional)

In your Postman environment, define:

- `SUPABASE_URL` — e.g. `https://YOUR_PROJECT_REF.supabase.co` or `http://127.0.0.1:54321`
- `SUPABASE_ANON_KEY` — anon/public key from Project Settings → API
- After step 1: `ACCESS_TOKEN`, `USER_ID`
- After step 2: `COURSE_ID`
- After step 3: `NOTE_ID`

Then use `{{VARIABLE}}` in URLs and bodies as above.

---

## Quick checklist

1. Sign in → copy `access_token` and `user.id`.
2. Get or create a course → copy `course_id`.
3. POST note → copy `note.id`.
4. POST PDF to `storage/v1/object/notes-pdfs/{{USER_ID}}/{{NOTE_ID}}.pdf` (body: binary PDF).
5. PATCH note with `metadata` containing `pdf_path`, `pdf_size_bytes`, `pdf_filename`, `pdf_uploaded_at`.
6. GET note to confirm `metadata` and, if supported, GET the object URL to confirm download.
