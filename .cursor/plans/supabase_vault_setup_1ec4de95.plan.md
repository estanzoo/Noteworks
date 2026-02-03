---
name: Supabase Vault Setup
overview: Enable and configure the Supabase Vault (Postgres extension) for storing encrypted secrets used inside the database (functions, triggers, webhooks), with access control and a short doc on when to use Vault vs project env vars.
todos: []
isProject: false
---

# Plan: Set Up Supabase Vault

**What Supabase Vault is:** A Postgres extension that stores secrets encrypted in the database. Secrets are available in decrypted form via a view (`vault.decrypted_secrets`) so you can use them in Postgres functions, triggers, and webhooks. Encryption is authenticated; backups and replication stay encrypted. This is **separate** from Auth OAuth credentials (Apple/Google), which live in Project Settings / env vars, not in Vault.

**When to use Vault:** For any secret that **Postgres** needs (e.g. API key used inside a DB function or webhook). Your 6-week plan later uses it for the OpenAI API key (Week 5). Auth provider client IDs/secrets stay in project config / env.

---

## 1. Enable the Vault extension

- Add a **migration** in [packages/supabase/supabase/migrations/](packages/supabase/supabase/migrations/) that runs:
  ```sql
  CREATE EXTENSION IF NOT EXISTS vault WITH SCHEMA vault;
  ```
- This keeps Vault version-controlled and applies the same way locally and on hosted projects (staging/production when you add them).
- After merging/running migrations, run `pnpm types:generate` only if you later add types that reference Vault; the extension does not change your `public` schema types.

---

## 2. Restrict access to decrypted secrets

- By default, consider who can read `vault.decrypted_secrets`. The docs recommend restricting access so only trusted roles can decrypt.
- In the **same migration** (or a follow-up), revoke public access and grant only to roles that need it, for example:
  - `postgres` (and thus dashboard/SQL editor) for admin use.
  - If an Edge Function or backend calls a Postgres function that reads from Vault, that usually runs as `service_role` or a dedicated role; grant that role access to the view, not to all authenticated users.
- Example pattern (adjust role names to match your setup):
  ```sql
  REVOKE ALL ON vault.decrypted_secrets FROM PUBLIC;
  GRANT SELECT ON vault.decrypted_secrets TO postgres;
  -- GRANT SELECT ON vault.decrypted_secrets TO service_role;  -- only if a server-side process needs it
  ```

---

## 3. Add and manage secrets

- **Option A — Dashboard:** In Supabase Dashboard go to **Database → Vault** (if available in your project). Add secrets via the UI (name + secret value). No code changes.
- **Option B — SQL:** Use the SQL editor or a one-off migration/seed script (do **not** commit real secret values). Example:
  ```sql
  SELECT vault.create_secret('your_secret_value', 'secret_name', 'Optional description');
  ```
- For **Week 1** you only need to confirm Vault works: enable the extension, optionally create a test secret via Dashboard or SQL, then delete it. Real secrets (e.g. OpenAI key) go in when you implement Week 5.
- **Updates:** Use `vault.update_secret(secret_uuid, new_value, new_name, new_description)` or replace via Dashboard.

---

## 4. Document “where secrets live” (optional but recommended)

- Add a short section (e.g. in [docs/Monorepo_Documentation.md](docs/Monorepo_Documentation.md) or a small `docs/backend/Secrets.md`) that states:
  - **Supabase Vault:** For secrets used **inside Postgres** (functions, triggers, webhooks). Enable via migration; add/rotate via Dashboard or SQL; access is restricted to selected roles.
  - **Project / env vars:** For **Auth** (Apple/Google OAuth) and **Edge Function** env vars — configured in Project Settings and/or `.env` for local (see [config.toml](packages/supabase/supabase/config.toml) `env(...)`). Not stored in Vault.
- This avoids confusion between “Supabase Vault” and “project environment variables.”

---

## Summary checklist


| Step | Action                                                                                                                                                                                             |
| ---- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 1    | New migration: `CREATE EXTENSION IF NOT EXISTS vault WITH SCHEMA vault;`                                                                                                                           |
| 2    | Same (or next) migration: `REVOKE`/`GRANT` on `vault.decrypted_secrets` so only trusted roles can read                                                                                             |
| 3    | Verify: run migration locally (`pnpm db:reset` or apply migration), then create one test secret via Dashboard or SQL and confirm it appears in `vault.decrypted_secrets`; remove test secret after |
| 4    | Optional: document Vault vs project env vars in a doc                                                                                                                                              |


No code implementation in app or Edge Functions is required for “setting up” Vault; using the stored secrets happens later when you add Postgres functions or webhooks that need them (e.g. Week 5 OpenAI).