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

// API Request Types
export interface CreateNoteRequest {
  title: string
  courseId?: string
  metadata?: Record<string, unknown>
}

export interface UpdateNoteRequest {
  title?: string
  metadata?: Record<string, unknown>
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
