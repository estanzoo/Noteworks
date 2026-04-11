# OAuth Setup Guide: Google & Apple Sign-In

This guide covers how to add Google and Apple OAuth to the Noteworks iOS app. It assumes Supabase and the Apple/Google developer consoles are already configured with credentials.

---

## What changes and what doesn't

### Backend: nothing changes

The existing backend works with OAuth users out of the box:

- **`requireAuth`** validates Bearer tokens regardless of how the user signed up (email, Google, Apple — they all produce the same Supabase JWT).
- **`handle_new_user` trigger** fires on any new `auth.users` row, creating the `public.users` profile. OAuth users get their name from `raw_user_meta_data->>'name'`, falling back to email.
- **`submit-onboarding`** and all other Edge Functions are provider-agnostic.

### Frontend: four areas change

1. `AuthService.swift` — new protocol methods + Supabase SDK calls
2. `AppleSignInHelper.swift` — new file wrapping `AuthenticationServices`
3. `WelcomeView.swift` — wire Google/Apple buttons to real actions
4. `OnboardingFlow.swift` — new handler methods + adjusted flow for OAuth users

---

## How OAuth sign-in works (overview)

```
┌──────────────┐
│  WelcomeView  │
│  [Google] btn │──► signInWithGoogle() ──► Supabase OAuth redirect ──► Google login page
│  [Apple]  btn │──► signInWithApple()  ──► Native ASAuthorizationController
└──────────────┘
        │
        ▼
   Supabase receives the provider token
        │
        ▼
   Creates/finds auth.users row ──► handle_new_user trigger ──► public.users row
        │
        ▼
   Returns a Supabase session (access_token + refresh_token)
        │
        ▼
   App receives AuthResult ──► same flow as email sign-in
        │
        ▼
   Check onboarding_completed_at ──► null? show onboarding : show main app
```

### Key difference from email sign-up

- **No email verification step** — the provider already verified the email.
- **No password** — the user authenticates with the provider.
- **Name may be missing** — Apple lets users hide their name; Google always provides one.
- **Email may be a relay** — Apple's "Hide My Email" gives a `@privaterelay.appleid.com` address. It still receives email.

---

## iOS implementation

### 1. Update `AuthServiceProtocol`

Add two new methods to the protocol in `AuthService.swift`:

```swift
protocol AuthServiceProtocol: AnyObject {
    // ... existing methods ...
    func signInWithGoogle() async throws -> AuthResult
    func signInWithApple() async throws -> AuthResult
}
```

### 2. Implement `signInWithApple()` in `SupabaseAuthService`

Apple Sign-In uses the native `ASAuthorizationController` to get an identity token, then passes it to Supabase via `signInWithIdToken`. This avoids any browser redirect on iOS.

```swift
import AuthenticationServices

func signInWithApple() async throws -> AuthResult {
    let helper = AppleSignInHelper()
    let credential = try await helper.performSignIn()
    let session = try await client.auth.signInWithIdToken(
        credentials: .init(
            provider: .apple,
            idToken: credential.idToken,
            nonce: credential.rawNonce
        )
    )
    return authResult(from: session, fallbackEmail: session.user.email ?? "")
}
```

**How it works:**
1. `AppleSignInHelper` presents the native Apple sign-in sheet.
2. User authenticates with Face ID / password.
3. Apple returns an `identityToken` (JWT) and the raw nonce.
4. Supabase validates the token with Apple's servers and creates/finds the user.
5. Supabase returns a normal session with `access_token`.

### 3. Implement `signInWithGoogle()` in `SupabaseAuthService`

Google uses the OAuth redirect flow. The Supabase Swift SDK opens an `ASWebAuthenticationSession` (in-app browser) automatically.

```swift
func signInWithGoogle() async throws -> AuthResult {
    let session = try await client.auth.signInWithOAuth(.google)
    return authResult(from: session, fallbackEmail: session.user.email ?? "")
}
```

**How it works:**
1. Supabase SDK opens a browser sheet pointed at Google's OAuth consent page.
2. User signs in with their Google account.
3. Google redirects back to `https://canhewvuprjwmpopcloj.supabase.co/auth/v1/callback`.
4. Supabase exchanges the code for tokens and redirects to the app's URL scheme.
5. The SDK intercepts the redirect and returns the session.

**Requires:** A URL scheme registered in the Xcode project so the redirect can return to the app (see Xcode setup below).

### 4. Create `AppleSignInHelper.swift`

New file at `Core/Auth/AppleSignInHelper.swift`. This wraps the `ASAuthorizationController` in an async/await API.

```swift
import AuthenticationServices
import CryptoKit

struct AppleSignInCredential {
    let idToken: String
    let rawNonce: String
}

final class AppleSignInHelper: NSObject,
    ASAuthorizationControllerDelegate,
    ASAuthorizationControllerPresentationContextProviding
{
    private var continuation: CheckedContinuation<AppleSignInCredential, Error>?
    private var rawNonce: String = ""

    @MainActor
    func performSignIn() async throws -> AppleSignInCredential {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            self.rawNonce = Self.randomNonce()
            let hashedNonce = SHA256.hash(data: Data(rawNonce.utf8))
                .compactMap { String(format: "%02x", $0) }.joined()

            let request = ASAuthorizationAppleIDProvider().createRequest()
            request.requestedScopes = [.fullName, .email]
            request.nonce = hashedNonce

            let controller = ASAuthorizationController(authorizationRequests: [request])
            controller.delegate = self
            controller.presentationContextProvider = self
            controller.performRequests()
        }
    }

    // MARK: - ASAuthorizationControllerDelegate

    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
              let tokenData = credential.identityToken,
              let idToken = String(data: tokenData, encoding: .utf8) else {
            continuation?.resume(throwing: URLError(.userAuthenticationRequired))
            return
        }
        continuation?.resume(returning: AppleSignInCredential(idToken: idToken, rawNonce: rawNonce))
    }

    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithError error: Error
    ) {
        continuation?.resume(throwing: error)
    }

    // MARK: - ASAuthorizationControllerPresentationContextProviding

    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow } ?? ASPresentationAnchor()
    }

    // MARK: - Nonce

    private static func randomNonce(length: Int = 32) -> String {
        let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        var remaining = length
        while remaining > 0 {
            var randoms = [UInt8](repeating: 0, count: 16)
            _ = SecRandomCopyBytes(kSecRandomDefault, randoms.count, &randoms)
            for byte in randoms where remaining > 0 {
                if byte < charset.count {
                    result.append(charset[Int(byte)])
                    remaining -= 1
                }
            }
        }
        return result
    }
}
```

**Why a nonce?** It prevents replay attacks. The raw nonce is sent to Supabase, and the hashed version is embedded in the Apple identity token. Supabase verifies they match.

### 5. Update `WelcomeView.swift`

The Google and Apple buttons currently both call `onSignUp`. Add dedicated callbacks:

```swift
struct WelcomeView: View {
    let onSignUp: () -> Void
    let onSignIn: () -> Void
    let onSkip: () -> Void
    let onGoogleSignIn: () -> Void   // new
    let onAppleSignIn: () -> Void    // new

    // ... body ...
}
```

Wire the buttons:

```swift
// Google button (was: action: onSignUp)
Button(action: onGoogleSignIn) {
    HStack(spacing: 10) {
        Image(systemName: "g.circle.fill")
        Text("Google")
    }
    // ... styling unchanged ...
}

// Apple button (was: action: onSignUp)
Button(action: onAppleSignIn) {
    HStack(spacing: 10) {
        Image(systemName: "apple.logo")
        Text("Apple")
    }
    // ... styling unchanged ...
}
```

### 6. Update `OnboardingFlow.swift`

Add handler methods and pass them to `WelcomeView`:

```swift
case .welcome:
    WelcomeView(
        onSignUp: { step = .signUp },
        onSignIn: { step = .signIn },
        onSkip: { step = .skipped },
        onGoogleSignIn: { handleGoogleSignIn() },   // new
        onAppleSignIn: { handleAppleSignIn() }       // new
    )
```

Handler methods:

```swift
private func handleGoogleSignIn() {
    isLoading = true
    Task {
        do {
            let result = try await appState.authService.signInWithGoogle()
            appState.handleAuthResult(result)
            step = .college   // skip sign-up + email verification
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription
                ?? error.localizedDescription
        }
        isLoading = false
    }
}

private func handleAppleSignIn() {
    isLoading = true
    Task {
        do {
            let result = try await appState.authService.signInWithApple()
            appState.handleAuthResult(result)
            step = .college   // skip sign-up + email verification
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription
                ?? error.localizedDescription
        }
        isLoading = false
    }
}
```

**Why skip to `.college`?** OAuth users don't need email verification (the provider already verified it). They also don't need to enter a name/password — Supabase gets the name from the provider. The onboarding steps for school, major, and interests still apply.

---

## Onboarding flow: OAuth vs email

### Email sign-up flow (unchanged)

```
Welcome → Sign Up → Verify Email → College → Major → Interests → Done
```

### OAuth sign-in flow (new)

```
Welcome → [Google/Apple button] → College → Major → Interests → Done
```

OAuth users skip:
- **Sign Up step** — no password needed
- **Verify Email step** — provider already verified

OAuth users still complete:
- **College** — school affiliation, year of study
- **Major** — school/department, major
- **Interests** — topic interests

### School email consideration

For email sign-up, `data.email` (the sign-up email) is used as `schoolEmail` in the onboarding payload. For OAuth users, the sign-in email may be a personal Gmail or an Apple relay address.

**Option A (simpler):** Use the OAuth email as `schoolEmail`. This works if you don't strictly need a `.edu` address.

**Option B (stricter):** Add a "School email" field to the College step for OAuth users. This lets them enter their `.edu` email separately from their sign-in email. To implement this:

1. Add a `schoolEmail` field to `OnboardingData`:
   ```swift
   @Published var schoolEmail = ""
   ```

2. Add an `isOAuthUser` flag to `OnboardingData` (set it after OAuth sign-in):
   ```swift
   @Published var isOAuthUser = false
   ```

3. In `CollegeStepView`, conditionally show the field:
   ```swift
   if data.isOAuthUser {
       OnboardingField(
           label: "School Email",
           placeholder: "you@university.edu",
           isEmail: true,
           text: $data.schoolEmail
       )
   }
   ```

4. In `OnboardingFlow.handleSubmitOnboarding()`, use the right email:
   ```swift
   schoolEmail: data.isOAuthUser
       ? data.schoolEmail.trimmingCharacters(in: .whitespacesAndNewlines)
       : data.email.trimmingCharacters(in: .whitespacesAndNewlines)
   ```

---

## Xcode project setup

### 1. Sign in with Apple capability

1. Open the Xcode project
2. Select the **Noteworks** target
3. Go to **Signing & Capabilities**
4. Click **+ Capability**
5. Add **Sign in with Apple**

Without this, `ASAuthorizationController` requests will fail silently.

### 2. URL scheme for Google OAuth redirect

Google OAuth uses a redirect flow. After the user signs in with Google, the browser needs to redirect back to the app. Register a URL scheme:

1. In Xcode, select the **Noteworks** target
2. Go to **Info** tab → **URL Types**
3. Click **+** and add:
   - **Identifier:** `com.googleusercontent.apps.YOUR_IOS_CLIENT_ID`
   - **URL Schemes:** `com.googleusercontent.apps.YOUR_IOS_CLIENT_ID` (the reversed client ID from Google Cloud Console)

### 3. Handle the callback URL

In your `App.swift` (or wherever the root `WindowGroup` is), add a URL handler so Supabase can receive the redirect:

```swift
@main
struct NoteworksApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .onOpenURL { url in
                    Task {
                        try? await appState.supabaseClient.auth.session(from: url)
                    }
                }
        }
    }
}
```

This tells the Supabase SDK to extract the session tokens from the redirect URL. It's only needed for the Google redirect flow — Apple uses native `signInWithIdToken` and doesn't redirect.

**Note:** For this to work, `appState` needs to expose the `SupabaseClient` (or you handle the URL in the auth service). One approach is to add a public accessor:

```swift
// In AppState.swift or AuthService.swift
var supabaseClient: SupabaseClient { (authService as! SupabaseAuthService).client }
```

Or make the `client` property on `SupabaseAuthService` internal instead of private.

---

## Returning OAuth users (sign-in after first time)

If a user previously signed in with Google/Apple and opens the app later:

1. The Supabase SDK checks for a stored session on init (via `emitLocalSessionAsInitialSession: true`, already configured in `SupabaseAuthService`).
2. If the session is still valid → the user is automatically signed in.
3. If expired → the SDK tries to refresh using the stored refresh token.
4. If refresh fails → user needs to sign in again.

For this to work reliably, Supabase needs to persist the session. The `supabase-swift` SDK stores sessions in Keychain by default, so this should work without additional code.

---

## File summary

| File | Status | What to do |
|------|--------|------------|
| `Core/Auth/AuthService.swift` | Edit | Add `signInWithGoogle()` and `signInWithApple()` to protocol + implementation |
| `Core/Auth/AppleSignInHelper.swift` | **New** | `ASAuthorizationController` wrapper with nonce generation |
| `Screens/Onboarding/Steps/WelcomeView.swift` | Edit | Add `onGoogleSignIn` / `onAppleSignIn` callbacks, wire to buttons |
| `Screens/Onboarding/OnboardingFlow.swift` | Edit | Add handlers, pass callbacks, skip to `.college` for OAuth |
| `Screens/Onboarding/OnboardingData.swift` | Edit (optional) | Add `schoolEmail` + `isOAuthUser` if collecting school email separately |
| `Screens/Onboarding/Steps/CollegeStepView.swift` | Edit (optional) | Show school email field for OAuth users |
| `App/AppState.swift` | Edit | Expose `SupabaseClient` for `.onOpenURL` handling |
| `App/NoteworksApp.swift` (or equivalent) | Edit | Add `.onOpenURL` handler for Google redirect |
| Xcode project | Config | Add Sign in with Apple capability + Google URL scheme |

---

## Quick reference: Supabase Swift SDK methods

| Provider | SDK method | Native UI? | Redirect needed? |
|----------|-----------|-----------|-----------------|
| Apple | `client.auth.signInWithIdToken(credentials:)` | Yes (Face ID sheet) | No |
| Google | `client.auth.signInWithOAuth(.google)` | No (in-app browser) | Yes (URL scheme) |
| Email | `client.auth.signIn(email:password:)` | N/A | No |
