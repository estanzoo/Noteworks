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
  pdf_path: string // e.g. "{user_id}/{note_id}.pdf"
  pdf_size_bytes: number
  pdf_filename: string
  pdf_uploaded_at: string // ISO 8601 timestamp
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

// Error types
export interface APIError {
  error: string
  message: string
  statusCode: number
  details?: unknown
}
