# Forgot Password: Supabase Setup Guide

This guide explains how to configure Supabase Auth so the **backend matches the Noteworks iOS app**. The app does **not** use “click a link in your email” for password reset. It uses a **6-digit recovery code** entered in the app, the same pattern as sign-up email verification.

---

## The mismatch (why this guide exists)

Supabase’s default **Reset password** email template sends a **magic link** (`{{ .ConfirmationURL }}`). The iOS app expects a **6-digit OTP** (`{{ .Token }}`) and verifies it with `verifyOTP(type: .recovery)`.

If you only change branding but leave the default link-only template, users will get an email with a link and **no usable code** for the in-app flow.

| | Default Supabase | Noteworks iOS |
|---|------------------|---------------|
| User action | Tap link in email | Enter 6-digit code in app |
| Step 1 API | `resetPasswordForEmail` | Same |
| Step 2 API | Often implicit via link | `verifyOTP` + `update(user:)` |
| Email must include | `{{ .ConfirmationURL }}` | **`{{ .Token }}`** (required) |

---

## What the frontend does (contract)

Password reset is implemented in `AuthService.swift` and used in two places:

1. **Onboarding** — Sign in → “Forgot password?” → email → 6-digit code + new password (`OnboardingFlow`, `ForgotPasswordView`, `ResetPasswordView`).
2. **Profile** — Security → Change password → same flow (`ProfileViewModel`, `PasswordChangePopup`).

### Step 1: Request a recovery code

```swift
try await client.auth.resetPasswordForEmail(email)
```

Maps to:

```http
POST https://app.noteworks.studio/auth/v1/recover
apikey: <anon key>
Content-Type: application/json

{ "email": "student@example.com" }
```

Supabase sends the **recovery** email template. That email must contain the OTP in `{{ .Token }}`.

### Step 2: Verify code and set new password

The app calls the **`confirm-password-reset`** Edge Function (server-side validation + Supabase Auth):

```http
POST https://app.noteworks.studio/functions/v1/confirm-password-reset
apikey: <anon key>
Content-Type: application/json

{
  "email": "student@example.com",
  "code": "123456",
  "password": "NewSecurePass123!",
  "confirm_password": "NewSecurePass123!"
}
```

Implementation: `packages/supabase/supabase/functions/confirm-password-reset/index.ts`

Client rules (enforced in UI, not only on server):

| Field | Rule |
|-------|------|
| Recovery code | Exactly **6 numeric digits** |
| New password | Minimum **8 characters** |
| Confirm password | Must match new password |

After a successful reset from onboarding, the user returns to **Sign in**. From Profile, they stay signed in with the new password.

### Resend

Calling `resetPasswordForEmail` again invalidates the previous code and sends a new one (same as onboarding resend and profile “Send code again”).

---

## End-to-end flow

```
┌─────────────────────┐
│ User enters email   │
│ (Forgot password)   │
└──────────┬──────────┘
           │
           ▼
   resetPasswordForEmail(email)
           │
           ▼
   Supabase sends "recovery" email
   MUST include {{ .Token }}  ◄── backend customization
           │
           ▼
┌─────────────────────┐
│ User enters 6-digit │
│ code + new password │
└──────────┬──────────┘
           │
           ▼
   POST /confirm-password-reset
   (verifyOtp + updateUser on server)
           │
           ▼
   Success → sign in (onboarding) or stay logged in (profile)
```

No Edge Functions or custom backend code are required. This is **Supabase Auth only** (same as sign-up OTP).

---

## Production: Supabase Dashboard

### 1. Customize the recovery email template

1. Open [Supabase Dashboard](https://supabase.com/dashboard) → your project → **Authentication** → **Email Templates**.
2. Select **Reset password** (template key: `recovery`).
3. Replace link-first content with OTP-first content.

**Subject example:**

```
Reset your Noteworks password
```

**Subject:** `Reset your NoteWorks password`

**Body:** Copy the full HTML from [`packages/supabase/supabase/templates/recovery.html`](../packages/supabase/supabase/templates/recovery.html) into the Dashboard template editor (same branded layout as signup verification; uses `{{ .Token }}` and `{{ .Email }}`).

**Important:**

- **`{{ .Token }}`** — required for the iOS app.
- **Avoid relying on `{{ .ConfirmationURL }}` alone** — the app never opens that link. Link-only emails break the flow.
- If you keep a link for web later, put it below the code and label it optional; do not remove `{{ .Token }}`.
- Corporate email “safe link” prefetch can consume one-click links before the user taps them; OTP avoids that ([Supabase docs](https://supabase.com/docs/guides/auth/auth-email-templates#email-prefetching)).

### 2. Align password policy

The app requires **8+ characters**. In Dashboard → **Authentication** → **Providers** → **Email**, set minimum password length to **8** (or lower only if you intentionally want the server to accept shorter passwords than the UI).

### 3. OTP expiry (optional)

Under **Authentication** → **Settings** (or **Auth** config), note **OTP expiry** (often 3600 seconds). The app does not show a countdown; if codes “expire too fast,” increase this value in hosted settings or in local `config.toml` (`auth.email.otp_expiry`).

### 4. SMTP (production)

Default Supabase email is fine for testing; for production use **Authentication** → **SMTP** with your provider ([Custom SMTP](https://supabase.com/docs/guides/auth/auth-smtp)). Disable **email tracking** in the provider so links/tokens are not rewritten.

### 5. Site URL and redirect URLs

For **OTP-only** reset, deep links are not required. Still set **Site URL** to something sensible (e.g. `https://noteworks.studio`) under **URL Configuration**. Redirect URLs matter if you later add a web reset page or `redirectTo` on `resetPasswordForEmail`; the current iOS code does not pass `redirectTo`.

### 6. Security notification (optional)

Enable **Password changed** notification email if you want users alerted after `auth.update(password)` succeeds.

---

## Local development

### Email inbox

With `supabase start`, auth emails are captured locally. Run:

```bash
cd packages/supabase && supabase status
```

Open the **Mailpit** (or legacy Inbucket) URL from the output and inspect the recovery message after triggering reset.

### `config.toml` + HTML template (recommended)

Add a recovery template under `packages/supabase/supabase/templates/` and wire it in `config.toml`.

Already configured in-repo:

- Template: `packages/supabase/supabase/templates/recovery.html`
- `config.toml`: `[auth.email.template.recovery]` with `content_path = "./templates/recovery.html"`

Restart local Supabase after changes:

```bash
supabase stop && supabase start
```

Copy the same subject/body into the hosted Dashboard when you deploy.

### Deploy the confirm-password-reset function

From `packages/supabase` (use **`npx`** — global `supabase` is not on PATH):

```bash
cd packages/supabase && npx supabase functions deploy confirm-password-reset
```

See `.cursor/rules/supabase-edge-functions.mdc` for the full deploy guide.

Hosted projects read `verify_jwt = false` from `config.toml` for this function so the iOS app can call it with only the anon key (no user session).

---

## Manual API testing (curl)

Use the project anon key from `SupabaseConfig.swift` / Dashboard → **API**.

**1. Request recovery email**

```bash
curl -s -X POST 'https://app.noteworks.studio/auth/v1/recover' \
  -H "apikey: YOUR_ANON_KEY" \
  -H "Content-Type: application/json" \
  -d '{"email":"your-test@example.com"}'
```

**2. Confirm code and set password** (use the 6-digit code from email / Mailpit)

```bash
curl -s -X POST 'https://app.noteworks.studio/functions/v1/confirm-password-reset' \
  -H "apikey: YOUR_ANON_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "email": "your-test@example.com",
    "code": "123456",
    "password": "NewSecurePass123!",
    "confirm_password": "NewSecurePass123!"
  }'
```

**3. Sign in with new password**

```bash
curl -s -X POST 'https://app.noteworks.studio/auth/v1/token?grant_type=password' \
  -H "apikey: YOUR_ANON_KEY" \
  -H "Content-Type: application/json" \
  -d '{"email":"your-test@example.com","password":"NewSecurePass123!"}'
```

---

## iOS test checklist

| # | Scenario | Expected |
|---|----------|----------|
| 1 | Sign in → Forgot password → valid email | Email arrives with **6-digit code** |
| 2 | Enter correct code + valid password (8+) | Returns to sign in; can log in with new password |
| 3 | Wrong code | “Invalid or expired code” (or similar) |
| 4 | Resend | New code works; old code fails |
| 5 | Profile → Change password (signed in) | Same email/code flow; stays logged in after success |
| 6 | OAuth-only account (no password) | Reset email may still send; setting password may enable email+password login — document for support if needed |

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---------|----------------|-----|
| Email has a link, no code | Default recovery template | Add `{{ .Token }}` to **Reset password** template |
| “Invalid or expired code” | Wrong code, expired OTP, or typo | Resend; check Mailpit/Dashboard logs; increase OTP expiry |
| No email at all | SMTP/rate limit / wrong project | Check Auth logs; configure SMTP; verify `app.noteworks.studio` project |
| Code works but password update fails | No session after `verifyOTP` | Ensure step 2 returns a session before `update(user:)` |
| UI says 8 chars, server rejects | Supabase min length > 8 or stricter rules | Align Dashboard password rules with app |
| Link in email “already used” | Email scanner prefetched URL | Prefer OTP-only template; drop primary reliance on `ConfirmationURL` |

---

## Related flows (same OTP pattern)

For consistency, configure these templates the same way (code in email, not link-only):

| Flow | Template | iOS `verifyOTP` type |
|------|----------|----------------------|
| Sign up | **Confirm signup** (`confirmation`) | `.signup` |
| Change email (profile) | **Change email address** (`email_change`) | `.emailChange` |
| Forgot password | **Reset password** (`recovery`) | `.recovery` |

See `AuthService.swift` for `verifyEmail`, `confirmEmailChange`, and `confirmPasswordReset`.

---

## Repo reference

| Area | Path |
|------|------|
| Confirm reset Edge Function | `packages/supabase/supabase/functions/confirm-password-reset/index.ts` |
| Recovery email template | `packages/supabase/supabase/templates/recovery.html` |
| Auth API | `apps/ios/Noteworks/Noteworks/Core/Auth/AuthService.swift` |
| Onboarding UI | `apps/ios/Noteworks/Noteworks/Screens/Onboarding/OnboardingFlow.swift`, `ForgotPasswordView.swift`, `ResetPasswordView.swift` |
| Profile password change | `apps/ios/Noteworks/Noteworks/Screens/Profile/ProfileViewModel.swift`, `PasswordChangePopup.swift` |
| Supabase local config | `packages/supabase/supabase/config.toml` |
| General auth overview | `docs/Frontend_Auth_and_Onboarding_Guide.md` |

---

## Official Supabase docs

- [Email templates](https://supabase.com/docs/guides/auth/auth-email-templates)
- [Customizing email templates (local)](https://supabase.com/docs/guides/local-development/customizing-email-templates)
- [Password-based auth (reset section)](https://supabase.com/docs/guides/auth/passwords)
- [Custom SMTP](https://supabase.com/docs/guides/auth/auth-smtp)
