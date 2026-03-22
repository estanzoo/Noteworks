import { Database } from './database.types'

// Helper type aliases
export type Tables<T extends keyof Database['public']['Tables']> =
  Database['public']['Tables'][T]['Row']

export type Insertable<T extends keyof Database['public']['Tables']> =
  Database['public']['Tables'][T]['Insert']

export type Updateable<T extends keyof Database['public']['Tables']> =
  Database['public']['Tables'][T]['Update']

// Model types (from your current schema)
export type User = Tables<'users'>
export type Course = Tables<'courses'>
export type School = Tables<'schools'>
export type SchoolCourse = Tables<'school_courses'>
export type SchoolEnrollment = Tables<'school_enrollments'>
export type CourseEnrollment = Tables<'course_enrollments'>
export type Note = Tables<'notes'>

// API Request Types
export interface CreateNoteRequest {
  title: string
  course_id: string
}

export interface UpdateNoteRequest {
  note_id: string
  title?: string
  metadata?: Record<string, unknown>
}

export interface UploadNotePdfParams {
  note_id: string
  filename?: string
  /** Required when the note_id is new (first upload creates the note row) */
  course_id?: string
  /** Defaults to filename without .pdf extension */
  title?: string
}

export interface UploadNotePdfResponse {
  success: boolean
}

export interface GetNotePdfUrlParams {
  note_id: string
  expires_in?: number
}

// API Response Types
export interface GetNotePdfUrlResponse {
  note_id: string
  pdf_filename: string | null
  signed_url: string
  expires_in: number
}

export interface DeleteNoteResponse {
  message: string
  id: string
}

export interface GetCoursesParams {
  page?: number
  pageSize?: number
  search?: string
}

export interface GetSchoolsParams {
  page?: number
  pageSize?: number
  search?: string
}

export interface GetSchoolCoursesParams {
  school_id: string
  page?: number
  pageSize?: number
  search?: string
}

/** GET /functions/v1/get-user-profile — returns the authenticated user's row */
export type GetUserProfileResponse = User

export interface GetNotesParams {
  id?: string
  course_id?: string
  page?: number
  pageSize?: number
  sortBy?: string
  sortOrder?: 'asc' | 'desc'
}

// PDF storage (stored in notes.metadata when a note has an attached PDF)
export interface NotePdfMetadata {
  pdf_path: string // e.g. "{user_id}/{note_id}/v_1.pdf"
  pdf_size_bytes: number
  pdf_filename: string
  pdf_uploaded_at: string // ISO 8601 timestamp
  version: number
  /** Storage paths of all previous versions (oldest first) */
  version_history: string[]
}

// Onboarding
export interface OnboardingSubmitRequest {
  name: string
  /** Expected graduation year, e.g. 2028 */
  year_of_graduation: number
  school_affiliation: string
  school_email: string
  /** Course codes the user is currently enrolled in (e.g. ["CS101", "MATH201"]) */
  course_codes: string[]
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

// ---------------------
// Community types
// ---------------------

// These will resolve to Tables<'...'> after regenerating database.types.ts.
// Until then they are defined as standalone interfaces matching the migration.

export interface Post {
  id: string
  user_id: string
  title: string
  body: string
  course_id: string | null
  visibility: string
  deleted_at: string | null
  likes_count: number
  comments_count: number
  created_at: string
  updated_at: string
}

export interface PostAttachment {
  post_id: string
  note_id: string
  created_at: string
}

export interface Hashtag {
  id: string
  name: string
  post_count: number
  created_at: string
}

export interface PostHashtag {
  post_id: string
  hashtag_id: string
}

export interface PostLike {
  post_id: string
  user_id: string
  created_at: string
}

export interface Comment {
  id: string
  post_id: string
  user_id: string
  parent_comment_id: string | null
  body: string
  likes_count: number
  visibility: string
  created_at: string
  updated_at: string
}

// Cursor-based pagination
export interface CursorPaginatedResponse<T> {
  data: T[]
  next_cursor: string | null
}

// Posts
export interface CreatePostRequest {
  title: string
  body: string
  visibility?: 'public' | 'private'
  course_id?: string
  attachment_note_ids?: string[]
  hashtags?: string[]
}

export interface UpdatePostRequest {
  post_id: string
  title?: string
  body?: string
  visibility?: 'public' | 'private'
  course_id?: string | null
  attachment_note_ids?: string[]
  hashtags?: string[]
}

export interface GetPostsParams {
  cursor?: string
  limit?: number
  user_id?: string
  hashtag?: string
  course_id?: string
  liked_by_me?: boolean
  include_own_private?: boolean
}

export interface AuthorInfo {
  id: string
  name: string | null
}

export interface AttachmentInfo {
  note_id: string
  title: string
}

export interface PostResponse {
  id: string
  user_id: string
  author: AuthorInfo
  title: string
  body: string
  visibility: string
  course_id: string | null
  likes_count: number
  comments_count: number
  has_liked: boolean
  hashtags: string[]
  attachments: AttachmentInfo[]
  created_at: string
  updated_at: string
}

export interface GetPostsResponse extends CursorPaginatedResponse<PostResponse> {
  data: PostResponse[]
}

export interface DeletePostResponse {
  message: string
  post_id: string
}

export interface LikePostRequest {
  post_id: string
}

export interface LikePostResponse {
  liked: boolean
  likes_count: number
}

// Comments
export interface CreateCommentRequest {
  post_id: string
  body: string
  parent_comment_id?: string
}

export interface GetCommentsParams {
  post_id: string
  cursor?: string
  limit?: number
}

export interface CommentResponse {
  id: string
  post_id: string
  user_id: string
  author: AuthorInfo
  parent_comment_id: string | null
  body: string
  likes_count: number
  visibility: string
  created_at: string
  updated_at: string
  replies: CommentResponse[]
}

export interface GetCommentsResponse extends CursorPaginatedResponse<CommentResponse> {
  data: CommentResponse[]
}

export interface DeleteCommentResponse {
  message: string
  comment_id: string
}

// Hashtags
export interface SearchHashtagsParams {
  q: string
  limit?: number
}

export interface HashtagResponse {
  id: string
  name: string
  post_count: number
}

// Error types
export interface APIError {
  error: string
  message: string
  statusCode: number
  details?: unknown
}
