# Noteworks Monorepo — Documentation

A pnpm + Turborepo monorepo for the Noteworks app (iOS + Supabase backend). This guide covers folder structure, scripts, the type system, and workflows for you and your collaborators.

---

## Table of Contents

1. [Folder Structure](#folder-structure)
2. [Scripts Reference](#scripts-reference)
3. [Types System](#types-system)
4. [Getting Started (Collaborators)](#getting-started-collaborators)
5. [Workflows](#workflows)
6. [Supabase Cloud (Link, Push, Pull)](#supabase-cloud-link-push-pull)
7. [Ports & Local URLs](#ports--local-urls)
8. [Secrets & Vault](#secrets--vault)

---

## Folder Structure

```
Noteworks/
├── apps/                    # Applications
│   └── ios/                 # iOS app (Swift/Xcode)
├── packages/                # Shared packages
│   ├── shared-types/        # TypeScript types (DB + API + models)
│   └── supabase/            # Supabase config, migrations, seed
├── scripts/                 # Build & codegen scripts
├── docs/                    # Documentation
├── .github/workflows/       # CI/CD (e.g. type sync)
├── package.json             # Root scripts & devDependencies
├── pnpm-workspace.yaml      # Workspace definition
├── turbo.json               # Turborepo config
└── tsconfig.json            # Base TypeScript config
```

### `apps/`

**Purpose:** Application entry points (web, mobile, etc.).

| Folder | Purpose |
|--------|---------|
| `apps/ios/` | iOS app for Noteworks. Add your Xcode project (`.xcodeproj` / `.xcworkspace`) here. Placeholder files (`.gitkeep`, `README.md`) keep the directory in git until the project exists. |

### `packages/`

**Purpose:** Shared code used by multiple apps.

| Folder | Purpose |
|--------|---------|
| `packages/shared-types/` | Single source of truth for types. Contains database types (generated from Supabase), API types, and business logic types. Consumed by TypeScript/JS and by Swift (via codegen). |
| `packages/supabase/` | Supabase backend. Holds config, migrations, seed data, and optional Edge Functions. |

### `packages/supabase/` (Details)

```
packages/supabase/
├── package.json
├── .env.local              # Secrets (gitignored) — copy from .env.example
└── supabase/
    ├── config.toml         # Local Supabase config (ports, auth, storage, etc.)
    ├── seed.sql            # Seed data for db reset
    ├── migrations/         # SQL migrations (ordered by timestamp)
    │   └── *_initial_schema.sql
    └── functions/          # (Optional) Edge Functions
```

### `scripts/`

**Purpose:** One-off and codegen scripts run via `pnpm`.

| File | Purpose |
|------|---------|
| `scripts/swift-codegen.ts` | Generates Swift types from `@noteworks/shared-types` for the iOS app. Run via `pnpm types:swift`. |
| `scripts/generate-migration.sh` | Helper to create new migrations. |

### `docs/`

**Purpose:** Project documentation.

| File | Purpose |
|------|---------|
| `Noteworks_Repo_Setup_Guide.md` | Step-by-step setup and configuration. |
| `Monorepo_Documentation.md` | This document. |

### `.github/workflows/`

**Purpose:** CI/CD and automation.

| File | Purpose |
|------|---------|
| `sync-types.yml` | Validates migrations apply and types generate. Runs on PRs/push when Supabase or shared-types change. Fails if the schema is broken or type generation errors. |

---

## Scripts Reference

All scripts are run from the **repository root** with `pnpm <script>`.

### Database

| Script | Command | Description |
|--------|---------|-------------|
| `db:start` | `pnpm db:start` | Start local Supabase stack (Postgres, Studio, Auth, etc.). Requires Docker. |
| `db:stop` | `pnpm db:stop` | Stop local Supabase. |
| `db:reset` | `pnpm db:reset` | Reset DB, re-run migrations, re-seed. Destructive. |
| `db:migrate` | `pnpm db:migrate` | Apply pending migrations to local DB. |
| `studio` | `pnpm studio` | Open Supabase Studio in the browser. |

### Types

| Script | Command | Description |
|--------|---------|-------------|
| `types:generate` | `pnpm types:generate` | Generate TypeScript types from local DB → `packages/shared-types/database.types.ts`. Requires Supabase running. |
| `types:swift` | `pnpm types:swift` | Generate Swift types from shared types (via `scripts/swift-codegen.ts`). |
| `types:sync` | `pnpm types:sync` | Run both `types:generate` and `types:swift`. |

### Development

| Script | Command | Description |
|--------|---------|-------------|
| `dev` | `pnpm dev` | Run all dev servers (Turborepo). |
| `build` | `pnpm build` | Build all packages. |
| `lint` | `pnpm lint` | Lint all packages. |
| `test` | `pnpm test` | Run tests. |

### Package-Specific Scripts

From `packages/supabase/`:

| Script | Command | Description |
|--------|---------|-------------|
| `migrate:new` | `cd packages/supabase && npx supabase migration new <name>` | Create a new migration file. |
| `types:gen` | `cd packages/supabase && npx supabase gen types typescript --local` | Generate DB types (use root `types:generate` to write to shared-types). |

---

## Types System

### Where Types Live

| File | Purpose | Generated? |
|------|---------|------------|
| `packages/shared-types/database.types.ts` | Supabase DB schema types (`Database`, tables, Row/Insert/Update) | Yes — by `pnpm types:generate` |
| `packages/shared-types/api.types.ts` | API request/response types, helpers (`Tables`, `Insertable`, `Updateable`), `User`, etc. | No |
| `packages/shared-types/models.ts` | Business logic types (`NoteMetadata`, `UserPreferences`, `StudySession`) | No |
| `packages/shared-types/index.ts` | Re-exports all types | No |

### How to Use Shared Types

**From another TypeScript/JavaScript package:**

```typescript
// Import everything
import { User, Database, CreateNoteRequest } from '@noteworks/shared-types'

// Import specific entry points
import type { Database } from '@noteworks/shared-types/database'
import type { PaginatedResponse, APIError } from '@noteworks/shared-types/api'
```

**Package exports (`packages/shared-types/package.json`):**

- `.` → `index.ts` (all types)
- `./database` → `database.types.ts`
- `./api` → `api.types.ts`

### Sharing Types with iOS (Swift)

1. **TypeScript → Swift:** Run `pnpm types:swift` (uses `scripts/swift-codegen.ts`).
2. **Output:** Swift models go under `apps/ios/Noteworks/Models/Generated/` (gitignored).
3. **Flow:** DB → `database.types.ts` → `swift-codegen.ts` → Swift files.

### Type Generation Workflow

```
1. Change schema (migrations in packages/supabase/supabase/migrations/)
2. pnpm db:migrate          # Apply migrations locally
3. pnpm types:generate      # Regenerate database.types.ts
4. pnpm types:swift         # Regenerate Swift types (optional)
```

### Important Notes

- `database.types.ts` is **gitignored** — each dev regenerates it locally.
- If you add new tables, update `api.types.ts` to export model aliases (e.g. `export type Note = Tables<'notes'>`).
- Keep `database.types.ts` in sync by running `pnpm types:generate` after pulling migrations or changing the schema.

---

## Getting Started (Collaborators)

### Prerequisites

- **Node.js** 18+
- **pnpm** (uses `packageManager` in `package.json`)
- **Docker Desktop** (for local Supabase)
- **Git**

### Setup

```bash
# 1. Clone the repo
git clone <repo-url>
cd Noteworks

# 2. Install dependencies
pnpm install

# 3. (Optional) Copy Supabase env template
# cp packages/supabase/.env.example packages/supabase/.env.local
# Edit .env.local with OAuth keys if needed

# 4. Start local Supabase (requires Docker)
pnpm db:start

# 5. Generate types from the local DB
pnpm types:generate
```

### First-Time Verification

```bash
pnpm studio        # Opens Supabase Studio
pnpm types:generate   # Should create/update database.types.ts
```

---

## Workflows

### Adding a New Migration

```bash
cd packages/supabase
npx supabase migration new add_notes_table
# Edit the new file in supabase/migrations/
cd ../..
pnpm db:migrate
pnpm types:generate
```

### Resetting the Database

```bash
pnpm db:stop
pnpm db:reset
pnpm types:generate
```

### Connecting the iOS App to Local Supabase

- **API URL:** `http://127.0.0.1:64321`
- **Anon key:** Shown when you run `pnpm db:start`
- On a physical device, use your machine’s LAN IP instead of `127.0.0.1`.

---

## Supabase Cloud (Link, Push, Pull)

Once you create a project at [supabase.com](https://supabase.com), link it to your local setup and sync migrations.

### Link to a Cloud Project

```bash
cd packages/supabase
npx supabase login
npx supabase link --project-ref <your-project-ref>
```

- **Project ref:** Dashboard → Project Settings → General → Reference ID

### Push Migrations (Local → Cloud)

Apply your local migrations to the linked cloud project:

```bash
cd packages/supabase
npx supabase db push
```

Or from the repo root:

```bash
pnpm db:migrate
```

### Pull Migrations (Cloud → Local)

If schema changes were made in the Supabase dashboard or elsewhere, pull them into your repo:

```bash
cd packages/supabase
npx supabase db pull
```

Creates a new migration file from the remote schema. Review it, then commit.

### Migration Scripts Summary

| Direction | Command | When to use |
|-----------|---------|-------------|
| Local → Cloud | `npx supabase db push` | After creating/editing migrations locally |
| Cloud → Local | `npx supabase db pull` | After schema changes in the dashboard or another environment |

### Generate Types from Cloud

```bash
cd packages/supabase
npx supabase gen types typescript --project-id <project-ref> > ../shared-types/database.types.ts
```

### Other Useful Commands

| Command | Purpose |
|---------|---------|
| `npx supabase db diff` | Show schema differences between local and remote |
| `npx supabase migration list` | List applied migrations on the linked project |
| `npx supabase db remote commit` | Create a migration from remote schema changes |

### Recommended Migration Flow

1. Create migrations locally: `npx supabase migration new <name>`
2. Edit the SQL file in `supabase/migrations/`
3. Test locally: `pnpm db:reset`
4. Push to cloud: `npx supabase db push`
5. Regenerate types: `pnpm types:generate` (local) or the cloud command above

---

## Ports & Local URLs

These ports are configured in `packages/supabase/supabase/config.toml` (changed from defaults to avoid conflicts on Windows):

| Service | Port | URL |
|---------|------|-----|
| API (PostgREST) | 64321 | http://127.0.0.1:64321 |
| Database (Postgres) | 64322 | postgresql://postgres:postgres@127.0.0.1:64322/postgres |
| Studio | 64323 | http://localhost:64323 |
| Inbucket (email) | 64324 | http://localhost:64324 |
| Analytics | 64327 | — |

---

## Secrets & Vault

Secrets are split by where they are used:

- **Supabase Vault:** For secrets used **inside Postgres** (functions, triggers, webhooks). Enabled via migration; add/rotate via Dashboard or SQL; access is restricted to selected roles. Vault is available on **Supabase Cloud** only, not in local Supabase.
- **Project / env vars:** For **Auth** (Apple/Google OAuth) and **Edge Function** env vars — configured in Project Settings and/or `.env` for local (see [config.toml](packages/supabase/supabase/config.toml) `env(...)`). Not stored in Vault.

See [docs/backend/Secrets.md](backend/Secrets.md) for details and verification steps.

---

## sync-types Workflow

**File:** `.github/workflows/sync-types.yml`

**Purpose:** Ensures migrations apply cleanly and TypeScript types can be generated from the schema. Catches broken migrations or type errors before they reach main.

**When it runs:** On pull requests and pushes to `main`/`master`, but only when files in `packages/supabase/` or `packages/shared-types/` change.

**What it does:**
1. Installs dependencies
2. Starts local Supabase (Docker)
3. Generates `database.types.ts` from the schema
4. Stops Supabase
5. Verifies `shared-types` builds with `tsc --noEmit`

**Why it can fail:**
- Migration SQL errors
- Schema changes that break type generation
- TypeScript errors in `shared-types` (e.g. `api.types.ts` references a table that no longer exists)

**Note:** `database.types.ts` is gitignored, so the workflow does not check for uncommitted type changes. It only validates that type generation succeeds. Run `pnpm types:generate` locally after pulling migrations.

---

## Troubleshooting

| Issue | Solution |
|-------|----------|
| `supabase` command not found | Scripts use `npx supabase`. Ensure `pnpm install` has been run. |
| Port already in use / forbidden | Ports use 64xxx to avoid Windows reserved ranges. Check `config.toml` for conflicts. |
| `database.types.ts` missing | Run `pnpm db:start` then `pnpm types:generate`. |
| Docker / virtualization errors | Enable virtualization in BIOS and ensure Docker Desktop can start. |
| `seed.sql` warning | An empty `seed.sql` exists. Add seed data if needed. |

---

## Further Reading

- [Noteworks_Repo_Setup_Guide.md](./Noteworks_Repo_Setup_Guide.md) — Detailed setup and schema examples
- [Supabase Local Development](https://supabase.com/docs/guides/cli/local-development)
- [pnpm Workspaces](https://pnpm.io/workspaces)
- [Turborepo](https://turbo.build/repo/docs)
