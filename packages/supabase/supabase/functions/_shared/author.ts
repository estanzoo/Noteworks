/**
 * Shared author-display helpers used by every community endpoint that
 * returns a post or comment with a joined `author:users(...)` row.
 *
 * Centralised so a single fallback rule applies everywhere — a user
 * with `users.name = null` shows up as their email prefix on every
 * surface, never as a stray "Anonymous".
 */

/**
 * Compute the display name shown on every post/comment card.
 *   1. `users.name` (trimmed) if non-empty.
 *   2. Otherwise, the email prefix (`alice@school.edu` -> `alice`).
 *   3. Final fallback "Student" if both are missing/empty.
 */
export function displayName(
  rawName: string | null | undefined,
  rawEmail: string | null | undefined,
): string {
  const trimmedName = (rawName ?? '').trim()
  if (trimmedName.length > 0) return trimmedName

  const email = (rawEmail ?? '').trim()
  if (email.length > 0) {
    const at = email.indexOf('@')
    const prefix = at > 0 ? email.slice(0, at) : email
    if (prefix.length > 0) return prefix
  }

  return 'Student'
}

/**
 * Return a trimmed string when it has content, or `null` otherwise.
 * Used when projecting nullable text columns (school_affiliation,
 * major, …) onto API responses so the client always sees either a
 * non-empty string or `null` — never `""` or `"   "`.
 */
export function nullIfBlank(raw: string | null | undefined): string | null {
  if (raw == null) return null
  const trimmed = raw.trim()
  return trimmed.length > 0 ? trimmed : null
}
