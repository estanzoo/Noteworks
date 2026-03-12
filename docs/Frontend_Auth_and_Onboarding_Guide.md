# Frontend Guide: Login, Sign-Up, and Onboarding

This guide explains how the iOS app should talk to the backend for authentication and onboarding. No backend experience needed.

---

## How the backend works (the basics)

The backend is a set of **API endpoints** — URLs that your app sends HTTP requests to. Think of them like functions you call over the internet. You send data (JSON), and they send data back (JSON).

Every request needs **two headers** (extra info attached to the request):

| Header          | Value                          | Why                                        |
|-----------------|--------------------------------|--------------------------------------------|
| `apikey`        | A fixed string (the "anon key") | Identifies which project you're talking to |
| `Authorization` | `Bearer <token>`               | Proves who the user is                     |

The **anon key** is the same for every user — it's not secret. Here it is:

```
eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImNhbmhld3Z1cHJqd21wb3BjbG9qIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Njk5NjI1NDgsImV4cCI6MjA4NTUzODU0OH0.jp-RcV0gxHHozwgL4pOlNkwUsjUbzoZTJ6MRJH4Oo8Y
```

The **token** (called an `access_token`) is unique per user session. You get it when the user signs in.

**Base URL for all requests:** `https://canhewvuprjwmpopcloj.supabase.co`

---

## The full flow (overview)

```
┌─────────────┐
│  App opens   │
└──────┬───────┘
       │
       ▼
  Has saved token?  ──── No ────► Show Login/Sign-Up screen
       │                                    │
      Yes                                   │
       │                          User signs up or signs in
       ▼                                    │
  GET /get-user-profile ◄───────────────────┘
       │
       ▼
  onboarding_completed_at is null?
       │                    │
      Yes                   No
       │                    │
       ▼                    ▼
  Show Onboarding      Show Main App
  screens                (Home, etc.)
       │
       ▼
  POST /submit-onboarding
       │
       ▼
  Show Main App
```

---

## Step 1: Sign Up (new user)

When a user creates an account for the first time.

**Request:**
```
POST https://canhewvuprjwmpopcloj.supabase.co/auth/v1/signup

Headers:
  apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImNhbmhld3Z1cHJqd21wb3BjbG9qIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Njk5NjI1NDgsImV4cCI6MjA4NTUzODU0OH0.jp-RcV0gxHHozwgL4pOlNkwUsjUbzoZTJ6MRJH4Oo8Y
  Content-Type: application/json

Body (JSON):
{
  "email": "student@gmail.com",
  "password": "SecurePass123!"
}
```

**What happens on the backend:**
1. Creates the user account
2. Sends a confirmation email (user must click the link)
3. Automatically creates a profile row in the database

**Response (success — 200):**
```json
{
  "access_token": "eyJhbGciOi...",
  "refresh_token": "abc123...",
  "token_type": "bearer",
  "expires_in": 3600,
  "user": {
    "id": "daab0df6-fad8-46e3-8fcd-2eae7a7a0e90",
    "email": "student@gmail.com",
    "email_confirmed_at": "2026-03-10T01:40:09Z",
    ...
  }
}
```

**What to save (in Keychain):**
- `access_token` — used for all future API calls
- `refresh_token` — used to get a new access_token when it expires

**Possible errors:**
| Status | Meaning | What to show the user |
|--------|---------|----------------------|
| 400 | Invalid email format | "Please enter a valid email" |
| 422 | Email already registered | "An account with this email already exists" |
| 400 | Weak password | "Password must be at least 6 characters" |

---

## Step 2: Sign In (returning user)

When a user already has an account and wants to log in.

**Request:**
```
POST https://canhewvuprjwmpopcloj.supabase.co/auth/v1/token?grant_type=password

Headers:
  apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImNhbmhld3Z1cHJqd21wb3BjbG9qIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Njk5NjI1NDgsImV4cCI6MjA4NTUzODU0OH0.jp-RcV0gxHHozwgL4pOlNkwUsjUbzoZTJ6MRJH4Oo8Y
  Content-Type: application/json

Body (JSON):
{
  "email": "student@gmail.com",
  "password": "SecurePass123!"
}
```

**Response:** Same shape as sign-up (includes `access_token`, `refresh_token`, `user`).

**What to save:** Same as sign-up — store both tokens in Keychain.

**Possible errors:**
| Status | Meaning | What to show the user |
|--------|---------|----------------------|
| 400 | Wrong email or password | "Invalid email or password" |
| 400 | Email not confirmed | "Please check your email and click the confirmation link" |

---

## Step 3: Get User Profile (check onboarding status)

After sign-in, fetch the user's profile to see if they've completed onboarding.

**Request:**
```
GET https://canhewvuprjwmpopcloj.supabase.co/functions/v1/get-user-profile

Headers:
  apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImNhbmhld3Z1cHJqd21wb3BjbG9qIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Njk5NjI1NDgsImV4cCI6MjA4NTUzODU0OH0.jp-RcV0gxHHozwgL4pOlNkwUsjUbzoZTJ6MRJH4Oo8Y
  Authorization: Bearer <access_token>
```

No body needed — this is a GET request.

**Response (success — 200):**
```json
{
  "id": "daab0df6-fad8-46e3-8fcd-2eae7a7a0e90",
  "email": "student@gmail.com",
  "name": "student@gmail.com",
  "year_of_graduation": null,
  "school_affiliation": null,
  "school_email": null,
  "course_codes": null,
  "onboarding_completed_at": null,
  "created_at": "2026-03-10T01:39:51Z",
  "updated_at": "2026-03-10T01:39:51Z"
}
```

**How to decide what to show:**
- If `onboarding_completed_at` is `null` → user hasn't onboarded → show onboarding screens
- If `onboarding_completed_at` has a value → user is done → show main app

---

## Step 4: Onboarding — Get list of schools

The first onboarding screen lets the user pick their school. Fetch the list from the backend.

**Request:**
```
GET https://canhewvuprjwmpopcloj.supabase.co/functions/v1/get-schools?page=1&pageSize=50

Headers:
  apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImNhbmhld3Z1cHJqd21wb3BjbG9qIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Njk5NjI1NDgsImV4cCI6MjA4NTUzODU0OH0.jp-RcV0gxHHozwgL4pOlNkwUsjUbzoZTJ6MRJH4Oo8Y
  Authorization: Bearer <access_token>
```

**To search/filter** (as the user types in a search bar):
```
GET .../get-schools?page=1&pageSize=20&search=MIT
```

**Response (success — 200):**
```json
{
  "data": [
    {
      "id": "s0000000-0000-0000-0000-000000000001",
      "name": "MIT",
      "location": "Cambridge, MA",
      "image": null,
      "created_at": "2026-01-01T00:00:00Z",
      "updated_at": "2026-01-01T00:00:00Z"
    },
    ...
  ],
  "pagination": {
    "page": 1,
    "pageSize": 50,
    "total": 12,
    "totalPages": 1,
    "hasMore": false
  }
}
```

Use `pagination.hasMore` to know if there are more pages to load (for infinite scroll or a "Load more" button).

---

## Step 5: Onboarding — Get courses for the selected school

After the user picks a school, show them courses offered at that school so they can select the ones they're taking.

**Request:**
```
GET https://canhewvuprjwmpopcloj.supabase.co/functions/v1/get-school-courses?school_id=THE_SCHOOL_ID&page=1&pageSize=50

Headers:
  apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImNhbmhld3Z1cHJqd21wb3BjbG9qIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Njk5NjI1NDgsImV4cCI6MjA4NTUzODU0OH0.jp-RcV0gxHHozwgL4pOlNkwUsjUbzoZTJ6MRJH4Oo8Y
  Authorization: Bearer <access_token>
```

**To search** (as the user types):
```
GET .../get-school-courses?school_id=THE_SCHOOL_ID&search=CS&page=1&pageSize=20
```

**Response (success — 200):**
```json
{
  "school": {
    "id": "s0000000-0000-0000-0000-000000000001",
    "name": "MIT"
  },
  "data": [
    {
      "id": "c0000000-0000-0000-0000-000000000001",
      "name": "Introduction to Computer Science",
      "code": "CS101",
      "description": "Intro to CS",
      "image": null,
      "users_enrolled_count": 42,
      "created_at": "...",
      "updated_at": "..."
    },
    ...
  ],
  "pagination": { "page": 1, "pageSize": 50, "total": 8, "totalPages": 1, "hasMore": false }
}
```

Save the selected course **codes** (e.g. `["CS101", "MATH201"]`) — you'll send these in the next step.

---

## Step 6: Onboarding — Submit

After the user has filled in their name, graduation year, school, school email, and selected courses, submit everything.

**Request:**
```
POST https://canhewvuprjwmpopcloj.supabase.co/functions/v1/submit-onboarding

Headers:
  apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImNhbmhld3Z1cHJqd21wb3BjbG9qIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Njk5NjI1NDgsImV4cCI6MjA4NTUzODU0OH0.jp-RcV0gxHHozwgL4pOlNkwUsjUbzoZTJ6MRJH4Oo8Y
  Authorization: Bearer <access_token>
  Content-Type: application/json

Body (JSON):
{
  "name": "Jane Smith",
  "year_of_graduation": 2028,
  "school_affiliation": "MIT",
  "school_email": "jsmith@mit.edu",
  "course_codes": ["CS101", "MATH201"]
}
```

**Field rules (the backend will reject invalid data):**

| Field | Type | Required | Rules |
|-------|------|----------|-------|
| `name` | string | Yes | 1–255 characters |
| `year_of_graduation` | integer | Yes | Between 2000 and 2100 |
| `school_affiliation` | string | Yes | 1–255 characters. Use the exact school name from the schools list. |
| `school_email` | string | Yes | Must be a valid email format, 1–255 characters |
| `course_codes` | string array | Yes (can be empty `[]`) | Max 50 items, each max 50 characters |

**Response (success — 200):**
```json
{
  "id": "daab0df6-...",
  "email": "student@gmail.com",
  "name": "Jane Smith",
  "year_of_graduation": 2028,
  "school_affiliation": "MIT",
  "school_email": "jsmith@mit.edu",
  "course_codes": ["CS101", "MATH201"],
  "onboarding_completed_at": "2026-03-10T02:15:00Z",
  "created_at": "...",
  "updated_at": "..."
}
```

After this succeeds, navigate to the main app.

**Validation error (400):**
```json
{
  "error": "Validation failed",
  "errors": {
    "name": "Name is required",
    "school_email": "Invalid email format"
  }
}
```

The `errors` object tells you exactly which fields have problems. Show these messages next to the corresponding form fields.

---

## Token management (important!)

### What are the tokens?

| Token | Lifetime | Purpose | Where to store |
|-------|----------|---------|----------------|
| `access_token` | 1 hour | Attached to every API call as proof of identity | Keychain |
| `refresh_token` | Days/weeks | Used to get a new `access_token` when it expires | Keychain |

### When the access token expires

After about 1 hour, API calls will start returning **401 (Unauthorized)**. When this happens:

1. Call the refresh endpoint to get a new access token
2. Save the new tokens
3. Retry the original request

**Refresh request:**
```
POST https://canhewvuprjwmpopcloj.supabase.co/auth/v1/token?grant_type=refresh_token

Headers:
  apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImNhbmhld3Z1cHJqd21wb3BjbG9qIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Njk5NjI1NDgsImV4cCI6MjA4NTUzODU0OH0.jp-RcV0gxHHozwgL4pOlNkwUsjUbzoZTJ6MRJH4Oo8Y
  Content-Type: application/json

Body (JSON):
{
  "refresh_token": "the-refresh-token-from-keychain"
}
```

**Response:** Same shape as sign-in — new `access_token` + new `refresh_token`. Save both.

**If refresh also fails (401):** The refresh token has expired too. The user needs to sign in again. Clear the Keychain and show the login screen.

### Recommended pattern

```
Every API call:
  1. Send request with access_token
  2. If response is 401:
     a. Try refreshing the token
     b. If refresh succeeds → retry the original request
     c. If refresh fails → sign out, show login screen
  3. Otherwise, handle the response normally
```

---

## App startup flow

When the app launches:

```
1. Check Keychain for saved access_token
   └── No token? → Show Login screen. Stop here.

2. Call GET /get-user-profile with the saved token
   ├── 401 error? → Try refreshing. If refresh fails → show Login screen.
   └── Success?
       ├── onboarding_completed_at is null → Show Onboarding screens
       └── onboarding_completed_at has value → Show Main App
```

---

## Quick reference: all endpoints used in this flow

| Step | Method | URL | Auth needed? |
|------|--------|-----|-------------|
| Sign up | POST | `/auth/v1/signup` | No (just apikey) |
| Sign in | POST | `/auth/v1/token?grant_type=password` | No (just apikey) |
| Refresh token | POST | `/auth/v1/token?grant_type=refresh_token` | No (just apikey) |
| Get profile | GET | `/functions/v1/get-user-profile` | Yes |
| Get schools | GET | `/functions/v1/get-schools?page=1&pageSize=20` | Yes |
| Get school courses | GET | `/functions/v1/get-school-courses?school_id=ID` | Yes |
| Submit onboarding | POST | `/functions/v1/submit-onboarding` | Yes |

"Auth needed" means the request needs `Authorization: Bearer <access_token>` in addition to the `apikey` header. Requests marked "No" only need the `apikey` header.

---

## Error format

All backend errors follow this format:

```json
{
  "error": "Short error type",
  "message": "Human-readable explanation",
  "statusCode": 400
}
```

Common status codes:
- **400** — Bad request (missing/invalid fields). Check the `errors` object for field-specific messages.
- **401** — Unauthorized (token missing, expired, or invalid). Try refreshing.
- **404** — Not found.
- **500** — Server error (not the frontend's fault). Show a generic "Something went wrong" message.
