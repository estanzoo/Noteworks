# Frontend Guide: Community Posts, Comments, and Hashtags

This guide explains how the iOS app should interact with the community feature. All endpoints follow the same patterns as the existing backend — same headers, same error format, same auth flow.

---

## How it works (overview)

The community feature adds a posts system where users can:
- Create posts with text, optional note attachments, and hashtags
- Browse a public feed with infinite scroll
- Like and unlike posts
- Comment on posts (with threaded replies)
- Search posts by hashtag or course
- View posts they've liked

All community endpoints live under `/functions/v1/` and require authentication (both `apikey` and `Authorization: Bearer <token>` headers).

---

## The feed flow

```
┌──────────────┐
│  Open Feed   │
└──────┬───────┘
       │
       ▼
  GET /get-posts?limit=20
       │
       ▼
  Show posts (title, body, author, likes count, hashtags)
       │
       ├── User scrolls down ──► GET /get-posts?cursor=LAST_CREATED_AT&limit=20
       │
       ├── User taps a post ──► GET /get-post?post_id=ID
       │                              │
       │                              ▼
       │                        Show full post + comments
       │                        GET /get-comments?post_id=ID
       │
       ├── User taps heart ──► POST /like-post  { post_id }
       │
       └── User taps "New Post" ──► POST /create-post  { title, body, ... }
```

---

## Cursor-based pagination (important!)

The community feed uses **cursor-based pagination** instead of page numbers. This works better for feeds where new content appears at the top.

**How it works:**
1. First request: `GET /get-posts?limit=20` (no cursor)
2. The response includes `next_cursor` — a timestamp string
3. Next request: `GET /get-posts?cursor=2026-03-22T10:30:00Z&limit=20`
4. Repeat until `next_cursor` is `null` (no more posts)

```
First load:     GET /get-posts?limit=20
                Response: { posts: [...20 items], next_cursor: "2026-03-22T10:30:00.000Z" }

Load more:      GET /get-posts?cursor=2026-03-22T10:30:00.000Z&limit=20
                Response: { posts: [...20 items], next_cursor: "2026-03-21T08:15:00.000Z" }

End of feed:    GET /get-posts?cursor=2026-03-01T00:00:00.000Z&limit=20
                Response: { posts: [...3 items], next_cursor: null }
```

---

## Creating a post

**Request:**
```
POST https://canhewvuprjwmpopcloj.supabase.co/functions/v1/create-post

Headers:
  apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImNhbmhld3Z1cHJqd21wb3BjbG9qIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Njk5NjI1NDgsImV4cCI6MjA4NTUzODU0OH0.jp-RcV0gxHHozwgL4pOlNkwUsjUbzoZTJ6MRJH4Oo8Y
  Authorization: Bearer <access_token>
  Content-Type: application/json

Body (JSON):
{
  "title": "My CS101 study notes",
  "body": "Here are the notes I took for chapter 5. Hope they help!",
  "visibility": "public",
  "course_id": "c0000000-0000-0000-0000-000000000001",
  "attachment_note_ids": ["note-uuid-1", "note-uuid-2"],
  "hashtags": ["cs101", "midterm", "studytips"]
}
```

**Field rules:**

| Field | Type | Required | Rules |
|-------|------|----------|-------|
| `title` | string | Yes | 1–255 characters |
| `body` | string | Yes | 1–10,000 characters |
| `visibility` | string | No | `"public"` (default) or `"private"` |
| `course_id` | string (UUID) | No | Must be a valid course ID if provided |
| `attachment_note_ids` | string[] | No | Array of note IDs the user has already uploaded. Max 10. |
| `hashtags` | string[] | No | Array of hashtag strings (no `#` prefix). Max 20. Lowercased automatically. |

**Response (success — 201):**
```json
{
  "id": "p0000000-0000-0000-0000-000000000001",
  "user_id": "daab0df6-fad8-46e3-8fcd-2eae7a7a0e90",
  "title": "My CS101 study notes",
  "body": "Here are the notes I took for chapter 5. Hope they help!",
  "visibility": "public",
  "course_id": "c0000000-0000-0000-0000-000000000001",
  "likes_count": 0,
  "comments_count": 0,
  "hashtags": ["cs101", "midterm", "studytips"],
  "attachments": ["note-uuid-1", "note-uuid-2"],
  "created_at": "2026-03-22T14:30:00Z",
  "updated_at": "2026-03-22T14:30:00Z"
}
```

**Possible errors:**

| Status | Meaning | What to show |
|--------|---------|-------------|
| 400 | Missing title or body, or invalid fields | Show field-specific errors |
| 401 | Not authenticated | Refresh token or show login |
| 404 | Course or note ID not found | "One of the attached items was not found" |

---

## Browsing the feed (get posts)

This is the main endpoint for loading the feed. It supports multiple filters through query parameters.

### Get the public feed (default)

```
GET https://canhewvuprjwmpopcloj.supabase.co/functions/v1/get-posts?limit=20

Headers:
  apikey: <anon_key>
  Authorization: Bearer <access_token>
```

### Filter by user (view someone's profile posts)

```
GET .../get-posts?user_id=USER_UUID&limit=20
```

This returns only **public** posts by that user. If `user_id` matches the current user, private posts are also included (see below).

### View your own posts (including private)

```
GET .../get-posts?user_id=YOUR_OWN_UUID&include_own_private=true&limit=20
```

### Filter by hashtag

```
GET .../get-posts?hashtag=midterm&limit=20
```

### Filter by course

```
GET .../get-posts?course_id=COURSE_UUID&limit=20
```

### Get posts you've liked

```
GET .../get-posts?liked_by_me=true&limit=20
```

### Combining filters

Filters can be combined:
```
GET .../get-posts?hashtag=studytips&course_id=COURSE_UUID&limit=20
```

### All query parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `limit` | integer | 20 | Number of posts per page (max 50) |
| `cursor` | string (ISO timestamp) | none | Pass `next_cursor` from previous response for next page |
| `user_id` | UUID | none | Filter by author |
| `hashtag` | string | none | Filter by hashtag name (no `#` prefix) |
| `course_id` | UUID | none | Filter by associated course |
| `liked_by_me` | boolean | false | Only return posts the current user has liked |
| `include_own_private` | boolean | false | Include your private posts (only works when `user_id` is yourself) |

**Response (success — 200):**
```json
{
  "posts": [
    {
      "id": "p0000000-0000-0000-0000-000000000001",
      "user_id": "daab0df6-fad8-46e3-8fcd-2eae7a7a0e90",
      "author": {
        "id": "daab0df6-fad8-46e3-8fcd-2eae7a7a0e90",
        "name": "Jane Smith"
      },
      "title": "My CS101 study notes",
      "body": "Here are the notes I took for chapter 5. Hope they help!",
      "visibility": "public",
      "course_id": "c0000000-0000-0000-0000-000000000001",
      "likes_count": 12,
      "comments_count": 3,
      "has_liked": false,
      "hashtags": ["cs101", "midterm", "studytips"],
      "attachments": [
        {
          "note_id": "note-uuid-1",
          "title": "Chapter 5 Notes"
        }
      ],
      "created_at": "2026-03-22T14:30:00Z",
      "updated_at": "2026-03-22T14:30:00Z"
    }
  ],
  "next_cursor": "2026-03-22T10:30:00.000Z"
}
```

Key fields to note:
- `has_liked` — boolean indicating whether the **current user** has liked this post. Use this to show a filled vs. empty heart icon.
- `author` — nested object with the post creator's name and ID.
- `attachments` — includes the note ID and its title for display.
- `next_cursor` — `null` when there are no more posts to load.

---

## Getting a single post (full details)

Use this when the user taps on a post to view its full detail page.

**Request:**
```
GET https://canhewvuprjwmpopcloj.supabase.co/functions/v1/get-post?post_id=POST_UUID

Headers:
  apikey: <anon_key>
  Authorization: Bearer <access_token>
```

**Response (success — 200):**
```json
{
  "id": "p0000000-0000-0000-0000-000000000001",
  "user_id": "daab0df6-fad8-46e3-8fcd-2eae7a7a0e90",
  "author": {
    "id": "daab0df6-fad8-46e3-8fcd-2eae7a7a0e90",
    "name": "Jane Smith"
  },
  "title": "My CS101 study notes",
  "body": "Here are the notes I took for chapter 5. Hope they help!",
  "visibility": "public",
  "course_id": "c0000000-0000-0000-0000-000000000001",
  "likes_count": 12,
  "comments_count": 3,
  "has_liked": false,
  "hashtags": ["cs101", "midterm", "studytips"],
  "attachments": [
    {
      "note_id": "note-uuid-1",
      "title": "Chapter 5 Notes"
    },
    {
      "note_id": "note-uuid-2",
      "title": "Lecture Slides Summary"
    }
  ],
  "created_at": "2026-03-22T14:30:00Z",
  "updated_at": "2026-03-22T14:30:00Z"
}
```

**Possible errors:**

| Status | Meaning | What to show |
|--------|---------|-------------|
| 400 | Missing `post_id` | — |
| 401 | Not authenticated | Refresh token or show login |
| 404 | Post not found or deleted | "This post is no longer available" |
| 403 | Private post owned by another user | "This post is private" |

---

## Updating a post

Only the post's author can update it.

**Request:**
```
PATCH https://canhewvuprjwmpopcloj.supabase.co/functions/v1/update-post

Headers:
  apikey: <anon_key>
  Authorization: Bearer <access_token>
  Content-Type: application/json

Body (JSON):
{
  "post_id": "p0000000-0000-0000-0000-000000000001",
  "title": "Updated title",
  "body": "Updated body text",
  "hashtags": ["cs101", "finals"]
}
```

Only include the fields you want to change. All fields except `post_id` are optional.

| Field | Type | Description |
|-------|------|-------------|
| `post_id` | UUID | **Required.** The post to update. |
| `title` | string | New title |
| `body` | string | New body |
| `visibility` | string | `"public"` or `"private"` |
| `course_id` | UUID or null | Change or remove the associated course |
| `attachment_note_ids` | string[] | **Replaces** the full attachment list. Omit to keep unchanged. |
| `hashtags` | string[] | **Replaces** the full hashtag list. Omit to keep unchanged. |

**Response (success — 200):** The updated post object (same shape as create-post response).

**Possible errors:**

| Status | Meaning | What to show |
|--------|---------|-------------|
| 400 | Invalid fields | Show field-specific errors |
| 401 | Not authenticated | Refresh token or show login |
| 403 | Not the post owner | "You can only edit your own posts" |
| 404 | Post not found or deleted | "This post is no longer available" |

---

## Deleting a post (soft delete)

Only the post's author can delete it. The post is **soft deleted** (marked as deleted but kept in the database), so it disappears from feeds but can be recovered if needed.

**Request:**
```
DELETE https://canhewvuprjwmpopcloj.supabase.co/functions/v1/delete-post?post_id=POST_UUID

Headers:
  apikey: <anon_key>
  Authorization: Bearer <access_token>
```

**Response (success — 200):**
```json
{
  "message": "Post deleted",
  "post_id": "p0000000-0000-0000-0000-000000000001"
}
```

**Possible errors:**

| Status | Meaning | What to show |
|--------|---------|-------------|
| 401 | Not authenticated | Refresh token or show login |
| 403 | Not the post owner | "You can only delete your own posts" |
| 404 | Post not found or already deleted | "This post is no longer available" |

---

## Liking / unliking a post

This is a **toggle** — call it once to like, call it again to unlike. The endpoint figures out which action to take.

**Request:**
```
POST https://canhewvuprjwmpopcloj.supabase.co/functions/v1/like-post

Headers:
  apikey: <anon_key>
  Authorization: Bearer <access_token>
  Content-Type: application/json

Body (JSON):
{
  "post_id": "p0000000-0000-0000-0000-000000000001"
}
```

**Response (success — 200):**
```json
{
  "liked": true,
  "likes_count": 13
}
```

Or if the user already liked it and this call removes the like:
```json
{
  "liked": false,
  "likes_count": 12
}
```

**How to use in the UI:**
- Use the `liked` boolean to toggle the heart icon (filled = liked, empty = not liked)
- Use `likes_count` to update the displayed count immediately (no need to re-fetch the post)

---

## Adding a comment

Comments support **threading** — a comment can be a reply to another comment.

### Top-level comment (reply to the post)

```
POST https://canhewvuprjwmpopcloj.supabase.co/functions/v1/create-comment

Headers:
  apikey: <anon_key>
  Authorization: Bearer <access_token>
  Content-Type: application/json

Body (JSON):
{
  "post_id": "p0000000-0000-0000-0000-000000000001",
  "body": "Great notes! This really helped me study."
}
```

### Reply to a comment (threaded)

```json
{
  "post_id": "p0000000-0000-0000-0000-000000000001",
  "body": "Glad they helped!",
  "parent_comment_id": "comment-uuid-being-replied-to"
}
```

**Field rules:**

| Field | Type | Required | Rules |
|-------|------|----------|-------|
| `post_id` | UUID | Yes | The post this comment belongs to |
| `body` | string | Yes | 1–5,000 characters |
| `parent_comment_id` | UUID | No | If replying to another comment, that comment's ID. Must belong to the same post. |

**Response (success — 201):**
```json
{
  "id": "cm000000-0000-0000-0000-000000000001",
  "post_id": "p0000000-0000-0000-0000-000000000001",
  "user_id": "daab0df6-fad8-46e3-8fcd-2eae7a7a0e90",
  "author": {
    "id": "daab0df6-fad8-46e3-8fcd-2eae7a7a0e90",
    "name": "Jane Smith"
  },
  "parent_comment_id": null,
  "body": "Great notes! This really helped me study.",
  "likes_count": 0,
  "visibility": "public",
  "created_at": "2026-03-22T15:00:00Z",
  "updated_at": "2026-03-22T15:00:00Z"
}
```

**Possible errors:**

| Status | Meaning | What to show |
|--------|---------|-------------|
| 400 | Missing post_id or body | Show field-specific errors |
| 401 | Not authenticated | Refresh token or show login |
| 404 | Post not found, deleted, or parent comment not found | "Could not add comment" |

---

## Getting comments for a post

Returns comments in **threaded** structure — top-level comments with their replies nested inside.

**Request:**
```
GET https://canhewvuprjwmpopcloj.supabase.co/functions/v1/get-comments?post_id=POST_UUID&limit=50

Headers:
  apikey: <anon_key>
  Authorization: Bearer <access_token>
```

**Query parameters:**

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `post_id` | UUID | **required** | The post to get comments for |
| `limit` | integer | 50 | Number of top-level comments per page (max 100) |
| `cursor` | string (ISO timestamp) | none | For loading more top-level comments |

**Response (success — 200):**
```json
{
  "comments": [
    {
      "id": "cm000000-0000-0000-0000-000000000001",
      "post_id": "p0000000-0000-0000-0000-000000000001",
      "user_id": "daab0df6-...",
      "author": {
        "id": "daab0df6-...",
        "name": "Jane Smith"
      },
      "parent_comment_id": null,
      "body": "Great notes! This really helped me study.",
      "likes_count": 5,
      "visibility": "public",
      "created_at": "2026-03-22T15:00:00Z",
      "updated_at": "2026-03-22T15:00:00Z",
      "replies": [
        {
          "id": "cm000000-0000-0000-0000-000000000002",
          "post_id": "p0000000-0000-0000-0000-000000000001",
          "user_id": "another-user-uuid",
          "author": {
            "id": "another-user-uuid",
            "name": "Bob Lee"
          },
          "parent_comment_id": "cm000000-0000-0000-0000-000000000001",
          "body": "Same here, especially the diagrams!",
          "likes_count": 2,
          "visibility": "public",
          "created_at": "2026-03-22T15:05:00Z",
          "updated_at": "2026-03-22T15:05:00Z",
          "replies": []
        }
      ]
    }
  ],
  "next_cursor": null
}
```

**How threading works in the UI:**
- Top-level comments (`parent_comment_id` is `null`) are at the root level
- Each comment has a `replies` array containing its direct child comments
- Replies can themselves have `replies` (nested arbitrarily deep)
- For deeply nested threads, consider collapsing after 2-3 levels with a "View more replies" button

---

## Deleting a comment

Only the comment's author can delete it. Comments are **hard deleted** — they're permanently removed along with any replies.

**Request:**
```
DELETE https://canhewvuprjwmpopcloj.supabase.co/functions/v1/delete-comment?comment_id=COMMENT_UUID

Headers:
  apikey: <anon_key>
  Authorization: Bearer <access_token>
```

**Response (success — 200):**
```json
{
  "message": "Comment deleted",
  "comment_id": "cm000000-0000-0000-0000-000000000001"
}
```

Note: If a comment has replies and the author deletes it, **all replies are also deleted** (cascade). Consider showing a confirmation dialog when the comment has replies.

---

## Searching hashtags (autocomplete)

Use this for the hashtag input field — as the user types, show matching suggestions.

**Request:**
```
GET https://canhewvuprjwmpopcloj.supabase.co/functions/v1/search-hashtags?q=study&limit=10

Headers:
  apikey: <anon_key>
  Authorization: Bearer <access_token>
```

**Query parameters:**

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `q` | string | **required** | Search prefix (e.g. `"stu"` matches `"studytips"`, `"study"`) |
| `limit` | integer | 10 | Max results (max 20) |

**Response (success — 200):**
```json
{
  "hashtags": [
    { "id": "h-uuid-1", "name": "studytips", "post_count": 42 },
    { "id": "h-uuid-2", "name": "studygroup", "post_count": 15 },
    { "id": "h-uuid-3", "name": "studying", "post_count": 8 }
  ]
}
```

Results are sorted by `post_count` (most popular first) — so the most relevant suggestions appear at the top.

**How to use in the UI:**
- Start searching after the user types 1-2 characters
- Show suggestions in a dropdown below the input
- Display `post_count` as a popularity indicator (e.g. "studytips · 42 posts")
- When the user selects a hashtag, add it as a tag/chip
- Users can also type brand new hashtags that don't exist yet — they'll be created when the post is submitted

---

## Typical UI scenarios

### Scenario 1: User opens the community tab
```
1. GET /get-posts?limit=20
2. Display posts in a scrollable list
3. Each post card shows: author name, title, body preview, hashtag chips,
   likes count, comments count, heart icon (filled if has_liked = true)
4. When user scrolls near bottom → GET /get-posts?cursor=NEXT_CURSOR&limit=20
```

### Scenario 2: User creates a post with notes attached
```
1. User writes title + body
2. User taps "Attach Notes" → show picker with their uploaded notes
3. User types hashtags → autocomplete via GET /search-hashtags?q=...
4. User taps "Post" → POST /create-post with all fields
5. On success → insert the new post at the top of the feed
```

### Scenario 3: User views a post and comments
```
1. GET /get-post?post_id=ID     → display full post
2. GET /get-comments?post_id=ID → display threaded comments
3. User types a comment → POST /create-comment { post_id, body }
4. On success → insert the new comment at the top of the list
```

### Scenario 4: User likes/unlikes a post from the feed
```
1. User taps heart icon → POST /like-post { post_id }
2. Response: { liked: true, likes_count: 13 }
3. Toggle heart to filled, update count to 13
4. User taps again → POST /like-post { post_id }
5. Response: { liked: false, likes_count: 12 }
6. Toggle heart to empty, update count to 12
```

### Scenario 5: User views their liked posts
```
1. GET /get-posts?liked_by_me=true&limit=20
2. Display in same list format as main feed
```

### Scenario 6: User taps a hashtag chip
```
1. GET /get-posts?hashtag=cs101&limit=20
2. Show a filtered feed with a header like "#cs101"
```

---

## Quick reference: all community endpoints

| Action | Method | URL | Auth? |
|--------|--------|-----|-------|
| Create post | POST | `/functions/v1/create-post` | Yes |
| Get posts (feed) | GET | `/functions/v1/get-posts` | Yes |
| Get single post | GET | `/functions/v1/get-post?post_id=ID` | Yes |
| Update post | PATCH | `/functions/v1/update-post` | Yes |
| Delete post | DELETE | `/functions/v1/delete-post?post_id=ID` | Yes |
| Like/unlike post | POST | `/functions/v1/like-post` | Yes |
| Create comment | POST | `/functions/v1/create-comment` | Yes |
| Get comments | GET | `/functions/v1/get-comments?post_id=ID` | Yes |
| Delete comment | DELETE | `/functions/v1/delete-comment?comment_id=ID` | Yes |
| Search hashtags | GET | `/functions/v1/search-hashtags?q=TERM` | Yes |

All endpoints require both the `apikey` header and `Authorization: Bearer <access_token>`.

---

## Error format

Same as all other backend errors:

```json
{
  "error": "Short error type",
  "message": "Human-readable explanation",
  "statusCode": 400
}
```

Common status codes:
- **400** — Bad request (missing/invalid fields).
- **401** — Unauthorized (token missing, expired, or invalid). Try refreshing.
- **403** — Forbidden (e.g. trying to edit/delete someone else's post).
- **404** — Not found (post deleted, comment doesn't exist, etc.).
- **500** — Server error. Show a generic "Something went wrong" message.
