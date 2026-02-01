# Noteworks Monorepo Setup - Step-by-Step Guide

## 🚀 Quick Start: Complete Setup Commands

Here's the exact sequence to get your monorepo up and running:

```bash
# 1. Create project directory
mkdir noteworks
cd noteworks

# 2. Initialize root package manager
pnpm init

# 3. Create monorepo structure
mkdir -p apps/ios
mkdir -p packages/supabase
mkdir -p packages/shared-types
mkdir -p scripts

# 4. Initialize Supabase
cd packages/supabase
npx supabase init
cd ../..

# 5. Set up workspace configuration
# (create files shown below)

# 6. Install dependencies
pnpm install

# 7. Start local Supabase
pnpm db:start
```

---

## 📦 Required Packages

### Root Level (Development Tools)

```json
{
  "name": "noteworks-monorepo",
  "version": "1.0.0",
  "private": true,
  "scripts": {
    "dev": "turbo dev",
    "build": "turbo build",
    "db:start": "cd packages/supabase && supabase start",
    "db:stop": "cd packages/supabase && supabase stop",
    "db:reset": "cd packages/supabase && supabase db reset",
    "db:migrate": "cd packages/supabase && supabase db push",
    "types:generate": "cd packages/supabase && supabase gen types typescript --local > ../shared-types/database.types.ts",
    "types:swift": "tsx scripts/swift-codegen.ts",
    "types:sync": "pnpm types:generate && pnpm types:swift",
    "studio": "cd packages/supabase && supabase studio",
    "lint": "turbo lint",
    "test": "turbo test"
  },
  "devDependencies": {
    "turbo": "^1.11.3",
    "supabase": "^1.142.2",
    "tsx": "^4.7.0",
    "typescript": "^5.3.3",
    "prettier": "^3.1.1",
    "eslint": "^8.56.0",
    "@typescript-eslint/eslint-plugin": "^6.19.0",
    "@typescript-eslint/parser": "^6.19.0"
  },
  "packageManager": "pnpm@8.15.1"
}
```

### Supabase Package

```json
{
  "name": "@noteworks/supabase",
  "version": "1.0.0",
  "private": true,
  "scripts": {
    "dev": "supabase start",
    "stop": "supabase stop",
    "reset": "supabase db reset",
    "migrate:new": "supabase migration new",
    "migrate:up": "supabase db push",
    "types:gen": "supabase gen types typescript --local",
    "studio": "supabase studio",
    "functions:serve": "supabase functions serve",
    "functions:deploy": "supabase functions deploy"
  },
  "dependencies": {},
  "devDependencies": {
    "supabase": "^1.142.2"
  }
}
```

### Shared Types Package

```json
{
  "name": "@noteworks/shared-types",
  "version": "1.0.0",
  "private": true,
  "main": "index.ts",
  "types": "index.ts",
  "exports": {
    ".": "./index.ts",
    "./database": "./database.types.ts",
    "./api": "./api.types.ts"
  },
  "scripts": {
    "build": "tsc",
    "lint": "eslint ."
  },
  "devDependencies": {
    "typescript": "^5.3.3"
  }
}
```

---

## 🏗️ Complete File Structure

```bash
# Create all directories and files
mkdir -p noteworks/{apps/ios,packages/{supabase,shared-types},scripts,.github/workflows}
cd noteworks

# Create workspace config
touch pnpm-workspace.yaml
touch turbo.json
touch .gitignore
touch README.md

# Create package files
touch package.json
touch packages/supabase/package.json
touch packages/shared-types/package.json

# Create TypeScript configs
touch tsconfig.json
touch packages/shared-types/tsconfig.json

# Create scripts
touch scripts/swift-codegen.ts
touch scripts/generate-migration.sh

# Create GitHub workflow
touch .github/workflows/sync-types.yml
```

---

## 📝 Configuration Files (Copy-Paste Ready)

### 1. `pnpm-workspace.yaml`
```yaml
packages:
  - 'apps/*'
  - 'packages/*'
```

### 2. `turbo.json`
```json
{
  "$schema": "https://turbo.build/schema.json",
  "globalDependencies": ["**/.env.*local"],
  "pipeline": {
    "build": {
      "dependsOn": ["^build"],
      "outputs": ["dist/**", ".next/**"]
    },
    "dev": {
      "cache": false,
      "persistent": true
    },
    "lint": {
      "dependsOn": ["^lint"]
    },
    "test": {
      "dependsOn": ["^test"]
    },
    "db:migrate": {
      "cache": false
    },
    "types:generate": {
      "cache": false,
      "outputs": ["packages/shared-types/**/*.ts"]
    }
  }
}
```

### 3. `.gitignore`
```gitignore
# Dependencies
node_modules/
.pnpm-store/

# Build outputs
dist/
build/
.turbo/

# Environment files
.env
.env*.local
!.env.example

# Supabase
.branches/
.temp/

# iOS
apps/ios/.build/
apps/ios/DerivedData/
apps/ios/*.xcodeproj/xcuserdata/
apps/ios/*.xcworkspace/xcuserdata/
apps/ios/Pods/

# Generated files
packages/shared-types/database.types.ts
apps/ios/Noteworks/Models/Generated/

# IDE
.vscode/
.idea/
*.swp
*.swo
*~

# OS
.DS_Store
Thumbs.db

# Logs
*.log
npm-debug.log*
yarn-debug.log*
yarn-error.log*
pnpm-debug.log*
```

### 4. Root `tsconfig.json`
```json
{
  "compilerOptions": {
    "target": "ES2022",
    "module": "ESNext",
    "lib": ["ES2022"],
    "moduleResolution": "bundler",
    "strict": true,
    "esModuleInterop": true,
    "skipLibCheck": true,
    "forceConsistentCasingInFileNames": true,
    "resolveJsonModule": true,
    "isolatedModules": true,
    "declaration": true,
    "declarationMap": true
  },
  "exclude": ["node_modules", "dist"]
}
```

### 5. `packages/shared-types/tsconfig.json`
```json
{
  "extends": "../../tsconfig.json",
  "compilerOptions": {
    "outDir": "./dist",
    "rootDir": ".",
    "composite": true
  },
  "include": ["./**/*.ts"],
  "exclude": ["node_modules", "dist"]
}
```

### 6. `packages/shared-types/index.ts`
```typescript
// Re-export all types
export * from './database.types'
export * from './api.types'
export * from './models'
```

### 7. `packages/shared-types/api.types.ts`
```typescript
import { Database } from './database.types'

// Helper type aliases
export type Tables<T extends keyof Database['public']['Tables']> = 
  Database['public']['Tables'][T]['Row']

export type Insertable<T extends keyof Database['public']['Tables']> = 
  Database['public']['Tables'][T]['Insert']

export type Updateable<T extends keyof Database['public']['Tables']> = 
  Database['public']['Tables'][T]['Update']

// Model types (will be generated from DB)
export type User = Tables<'users'>
export type Note = Tables<'notes'>
export type Course = Tables<'courses'>
export type School = Tables<'schools'>

// API Request Types
export interface CreateNoteRequest {
  title: string
  courseId?: string
  metadata?: Record<string, any>
}

export interface UpdateNoteRequest {
  title?: string
  metadata?: Record<string, any>
}

export interface AISummaryRequest {
  noteId: string
  scope: 'full_note' | 'current_page' | 'selection'
  content?: string
}

export interface AISummaryResponse {
  keyPoints: string[]
  concepts: string[]
  summary: string
  cached: boolean
}

export interface CreateFlashcardsRequest {
  noteId: string
  count: number
  difficulty: 'easy' | 'medium' | 'hard'
}

export interface Flashcard {
  question: string
  answer: string
  hint?: string
  difficulty: string
  topic: string
}

export interface CreateFlashcardsResponse {
  flashcards: Flashcard[]
  cached: boolean
}

export interface CombineNotesRequest {
  noteIds: string[]
  strategy: 'merge' | 'compare' | 'synthesize'
}

export interface CombineNotesResponse {
  mergedContent: string
  sourceMap: Record<string, string[]>
  conflicts?: string[]
}

// Pagination
export interface PaginationParams {
  page?: number
  pageSize?: number
  sortBy?: string
  sortOrder?: 'asc' | 'desc'
}

export interface PaginatedResponse<T> {
  data: T[]
  pagination: {
    page: number
    pageSize: number
    total: number
    totalPages: number
    hasMore: boolean
  }
}

// Error types
export interface APIError {
  error: string
  message: string
  statusCode: number
  details?: any
}
```

### 8. `packages/shared-types/models.ts`
```typescript
// Additional business logic types that don't come from the database

export interface NoteMetadata {
  pageCount?: number
  canvasWidth?: number
  canvasHeight?: number
  backgroundColor?: string
  tags?: string[]
  colorPalette?: string[]
}

export interface UserPreferences {
  defaultPenColor?: string
  defaultPenWidth?: number
  autoSaveInterval?: number
  theme?: 'light' | 'dark' | 'auto'
}

export interface StudySession {
  noteId: string
  duration: number
  activitiesCompleted: string[]
  startedAt: Date
  endedAt: Date
}
```

---

## 🗄️ Supabase Setup

### Initialize Supabase
```bash
cd packages/supabase
npx supabase init
```

This creates:
```
packages/supabase/
├── supabase/
│   ├── config.toml          # Supabase configuration
│   ├── seed.sql             # Seed data
│   └── migrations/          # Database migrations
└── package.json
```

### Configure `supabase/config.toml`

The default config is good, but here are key settings to verify:

```toml
# packages/supabase/supabase/config.toml

[api]
enabled = true
port = 54321
schemas = ["public", "storage"]
extra_search_path = ["public"]
max_rows = 1000

[db]
port = 54322
shadow_port = 54320
major_version = 15

[db.pooler]
enabled = false
port = 54329
pool_mode = "transaction"
default_pool_size = 20
max_client_conn = 100

[realtime]
enabled = true
ip_version = "ipv4"
port = 54323

[studio]
enabled = true
port = 54324
api_url = "http://127.0.0.1"

[inbucket]
enabled = true
port = 54325
smtp_port = 54326
pop3_port = 54327

[storage]
enabled = true
file_size_limit = "50MiB"

[auth]
enabled = true
site_url = "http://127.0.0.1:3000"
additional_redirect_urls = ["https://127.0.0.1:3000"]
jwt_expiry = 3600
enable_refresh_token_rotation = true
refresh_token_reuse_interval = 10
enable_signup = true

[auth.external.apple]
enabled = true
client_id = "env(APPLE_CLIENT_ID)"
secret = "env(APPLE_SECRET)"

[auth.external.google]
enabled = true
client_id = "env(GOOGLE_CLIENT_ID)"
secret = "env(GOOGLE_SECRET)"

[edge_functions]
enabled = true
```

### Create `.env.local` for Supabase

```bash
# packages/supabase/.env.local

# OAuth providers (will be filled in later)
APPLE_CLIENT_ID=
APPLE_SECRET=

GOOGLE_CLIENT_ID=
GOOGLE_SECRET=

# OpenAI API for AI features
OPENAI_API_KEY=

# Optional: Anthropic Claude API
ANTHROPIC_API_KEY=
```

---

## 📊 First Database Migration

### Create initial schema migration

```bash
cd packages/supabase
npx supabase migration new initial_schema
```

This creates: `supabase/migrations/[timestamp]_initial_schema.sql`

### Edit the migration file:

```sql
-- packages/supabase/supabase/migrations/[timestamp]_initial_schema.sql

-- Enable required extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- Users table (extends Supabase auth.users)
CREATE TABLE public.users (
    id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    email TEXT UNIQUE NOT NULL,
    name TEXT,
    credits INTEGER NOT NULL DEFAULT 100,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Schools table
CREATE TABLE public.schools (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name TEXT NOT NULL,
    country TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Courses table
CREATE TABLE public.courses (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    school_id UUID REFERENCES schools(id) ON DELETE CASCADE,
    code TEXT NOT NULL,
    name TEXT NOT NULL,
    description TEXT,
    member_count INTEGER DEFAULT 0,
    note_count INTEGER DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Notes table
CREATE TABLE public.notes (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID REFERENCES users(id) ON DELETE CASCADE NOT NULL,
    course_id UUID REFERENCES courses(id) ON DELETE SET NULL,
    title TEXT NOT NULL,
    
    -- File storage references
    drawing_url TEXT,
    thumbnail_url TEXT,
    
    -- Drawing metadata
    page_count INTEGER DEFAULT 1,
    canvas_width INTEGER,
    canvas_height INTEGER,
    file_size_bytes BIGINT,
    file_hash TEXT,
    
    -- Additional metadata
    metadata JSONB,
    
    -- Version control
    version INTEGER DEFAULT 1,
    
    -- Timestamps
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    last_synced_at TIMESTAMPTZ,
    deleted_at TIMESTAMPTZ
);

-- Indexes for performance
CREATE INDEX idx_users_email ON users(email);
CREATE INDEX idx_notes_user_id ON notes(user_id);
CREATE INDEX idx_notes_course_id ON notes(course_id);
CREATE INDEX idx_notes_created_at ON notes(created_at DESC);
CREATE INDEX idx_notes_updated_at ON notes(updated_at DESC);
CREATE INDEX idx_courses_school_id ON courses(school_id);

-- Enable Row Level Security
ALTER TABLE users ENABLE ROW LEVEL SECURITY;
ALTER TABLE notes ENABLE ROW LEVEL SECURITY;
ALTER TABLE courses ENABLE ROW LEVEL SECURITY;
ALTER TABLE schools ENABLE ROW LEVEL SECURITY;

-- RLS Policies for users
CREATE POLICY "Users can view own profile"
    ON users FOR SELECT
    USING (auth.uid() = id);

CREATE POLICY "Users can update own profile"
    ON users FOR UPDATE
    USING (auth.uid() = id);

-- RLS Policies for notes
CREATE POLICY "Users can view own notes"
    ON notes FOR SELECT
    USING (auth.uid() = user_id AND deleted_at IS NULL);

CREATE POLICY "Users can create notes"
    ON notes FOR INSERT
    WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update own notes"
    ON notes FOR UPDATE
    USING (auth.uid() = user_id);

CREATE POLICY "Users can delete own notes"
    ON notes FOR DELETE
    USING (auth.uid() = user_id);

-- RLS Policies for courses (public read)
CREATE POLICY "Anyone can view courses"
    ON courses FOR SELECT
    TO authenticated
    USING (true);

-- RLS Policies for schools (public read)
CREATE POLICY "Anyone can view schools"
    ON schools FOR SELECT
    TO authenticated
    USING (true);

-- Trigger to update updated_at timestamp
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER update_users_updated_at
    BEFORE UPDATE ON users
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_notes_updated_at
    BEFORE UPDATE ON notes
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

-- Function to handle new user creation
CREATE OR REPLACE FUNCTION handle_new_user()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO public.users (id, email, name)
    VALUES (
        NEW.id,
        NEW.email,
        COALESCE(NEW.raw_user_meta_data->>'name', NEW.email)
    );
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Trigger to create user profile on signup
CREATE TRIGGER on_auth_user_created
    AFTER INSERT ON auth.users
    FOR EACH ROW
    EXECUTE FUNCTION handle_new_user();
```

---

## 🚀 Start Everything

### 1. Install all dependencies
```bash
# From root
pnpm install
```

### 2. Start Supabase locally
```bash
pnpm db:start
```

This will:
- Start PostgreSQL database
- Start Supabase Studio (http://localhost:54323)
- Apply migrations
- Show you connection details

### 3. Generate TypeScript types
```bash
pnpm types:generate
```

This creates `packages/shared-types/database.types.ts`

### 4. View Supabase Studio
```bash
pnpm studio
# Opens http://localhost:54323
```

---

## 📋 Useful Commands Reference

```bash
# Database
pnpm db:start          # Start local Supabase
pnpm db:stop           # Stop local Supabase
pnpm db:reset          # Reset database (destructive!)
pnpm db:migrate        # Apply migrations
pnpm studio            # Open Supabase Studio

# Types
pnpm types:generate    # Generate TypeScript types from DB
pnpm types:swift       # Generate Swift types
pnpm types:sync        # Generate both

# Migrations
cd packages/supabase
npx supabase migration new <name>    # Create new migration
npx supabase db diff                 # Show schema changes
npx supabase db push                 # Apply migrations

# Development
pnpm dev               # Start all dev servers (when you add apps)
pnpm build             # Build all packages
pnpm lint              # Lint all packages
```

---

## ✅ Verification Checklist

After setup, verify everything works:

```bash
# 1. Check Supabase is running
pnpm db:start
# Should see: Started supabase local development setup.

# 2. Check Studio opens
pnpm studio
# Should open browser to http://localhost:54323

# 3. Check types generated
ls -la packages/shared-types/database.types.ts
# Should see the generated file

# 4. Check migration applied
# In Supabase Studio > Database > Tables
# Should see: users, schools, courses, notes

# 5. Test a query in Studio
# Run: SELECT * FROM users;
# Should work (empty results is fine)
```

---

## 🎯 Next Steps

After repo setup:

1. **Week 1 Tasks:**
   - Set up OAuth providers (Apple + Google)
   - Create seed data
   - Test authentication flow

2. **Week 2 Tasks:**
   - Set up Supabase Storage buckets
   - Create first Edge Function
   - Test file upload

3. **iOS Integration:**
   - Add supabase-swift package
   - Configure Xcode project
   - Connect to local Supabase

---

## 🔧 Troubleshooting

**Supabase won't start:**
```bash
# Check if Docker is running
docker ps

# Reset Supabase completely
pnpm db:stop
rm -rf packages/supabase/.branches
pnpm db:start
```

**Types not generating:**
```bash
# Make sure Supabase is running
pnpm db:start

# Generate manually
cd packages/supabase
npx supabase gen types typescript --local > ../shared-types/database.types.ts
```

**Port conflicts:**
```bash
# Check what's using the ports
lsof -i :54321  # API
lsof -i :54323  # Studio

# Kill the process or change ports in config.toml
```

---

This setup gives you a production-ready monorepo structure that's ready for the 6-week MVP development!
