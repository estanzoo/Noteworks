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
