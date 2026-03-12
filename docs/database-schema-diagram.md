# Noteworks Database Schema

![Database schema diagram](./database-schema-diagram.png)

## Mermaid (editable)

```mermaid
erDiagram
    auth_users {
        uuid id PK
        text email
        jsonb raw_user_meta_data
    }

    users {
        uuid id PK,FK
        text email
        text name
        int year_of_graduation
        text school_affiliation
        text school_email
        text_array course_codes
        timestamptz onboarding_completed_at
        timestamptz created_at
        timestamptz updated_at
    }

    schools {
        uuid id PK
        text name
        text location
        text image
        timestamptz created_at
        timestamptz updated_at
    }

    courses {
        uuid id PK
        text name
        text code
        text description
        text image
        int users_enrolled_count
        timestamptz created_at
        timestamptz updated_at
    }

    school_courses {
        uuid school_id PK,FK
        uuid course_id PK,FK
        timestamptz created_at
    }

    school_enrollments {
        uuid school_id PK,FK
        uuid user_id PK,FK
        timestamptz enrolled_at
    }

    course_enrollments {
        uuid course_id PK,FK
        uuid user_id PK,FK
        timestamptz enrolled_at
    }

    notes {
        uuid id PK
        uuid course_id FK
        uuid user_id FK
        text title
        jsonb metadata
        timestamptz created_at
        timestamptz updated_at
    }

    auth_users ||--|| users : "extends"
    users ||--o{ school_enrollments : "enrolled in"
    schools ||--o{ school_enrollments : "has"
    users ||--o{ course_enrollments : "enrolled in"
    courses ||--o{ course_enrollments : "has"
    schools ||--o{ school_courses : "offers"
    courses ||--o{ school_courses : "offered by"
    courses ||--o{ notes : "has"
    users ||--o{ notes : "uploaded by"
```

## Table summary

| Table | Purpose |
|-------|--------|
| **users** | Profile for each auth user; extends `auth.users` |
| **schools** | Schools/institutions |
| **courses** | Course catalog (name, code, description) |
| **school_courses** | Which courses each school offers |
| **school_enrollments** | Which users are enrolled in which schools |
| **course_enrollments** | Which users are enrolled in which courses |
| **notes** | Notes uploaded to a course by a user |

## Relationships

- **users** ↔ **schools**: many-to-many via `school_enrollments`
- **users** ↔ **courses**: many-to-many via `course_enrollments`
- **schools** ↔ **courses**: many-to-many via `school_courses`
- **notes**: belongs to one **course** and one **user** (uploader)
