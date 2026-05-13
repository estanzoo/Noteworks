# Manual Testing Guide

A step-by-step playbook for testing Noteworks, from the fastest feedback loop (Xcode previews) all the way to TestFlight. For each level there's what it's good for, what it can't test, and how to do it.

---

## Level 0 — Prerequisites (one-time setup)

1. Open the project: `apps/ios/Noteworks/Noteworks.xcodeproj`.
2. Top-left of Xcode → make sure the scheme says **Noteworks** (not `NoteworksTests`).
3. Sign in to your Apple ID in Xcode → `Settings → Accounts → "+"`. Required for running on a real device.
4. Pick your team:
  - `Noteworks` target → **Signing & Capabilities → Team** → select your personal team (or your Apple Developer team for TestFlight).
5. Make sure you have two Supabase test accounts ready (e.g. `test-a@example.com`, `test-b@example.com`) — Plan 1 (Community) needs two real users on the hosted backend to test cross-user behaviour.

---

## Level 1 — Xcode SwiftUI Previews (fastest, ~5 seconds)

**Good for:** UI layout, colors, fonts, dark/light mode, empty states, individual screens.
**Can't test:** Networking, real auth, real PDF upload, multi-user flows, persistence.

### Steps

1. Open a view file, e.g. `Screens/Community/CommunityView.swift`.
2. Press `⌘+Option+Return` to open the canvas.
3. Click **Resume** (or `⌘+Option+P`) — Xcode builds the preview.
4. To preview as iPad: click the **Devices** dropdown at the bottom of the canvas → pick "iPad Pro 13-inch (M4)" or similar.
5. Press the **Play** button on the canvas to make it interactive (taps and scroll work).

### What to check at this level

- Community feed renders the "Start a new post…" card.
- Post detail popup, comment item, post editor all look right.
- Profile screen, Home, Onboarding steps look right.

### Tip

If a preview is broken, the `#Preview { ... }` block at the bottom of the file usually shows which env objects are needed. Most use `AppState(notesStore: NotesStore.preview())`.

---

## Level 2 — iOS Simulator (most of your daily testing)

**Good for:** Full app flows, networking, sign-up/sign-in, posting, commenting, liking, drawing notes, profile editing.
**Can't test:** Apple Pencil, real cellular network, real camera, real file picker behaviour, TestFlight-specific behaviour.

### Steps

1. In Xcode's top bar, click the device selector (next to the scheme name).
2. Pick **iPad Pro 13-inch (M4)** or **iPad Air 11-inch (M3)** — the app is iPad-first.
3. Press `⌘+R` (or the Play button) to build and run.
4. The simulator opens; the app launches.

### Useful simulator shortcuts


| Shortcut                                  | Action                                                                                     |
| ----------------------------------------- | ------------------------------------------------------------------------------------------ |
| `⌘+Shift+H`                               | Home button                                                                                |
| `⌘+L`                                     | Lock screen                                                                                |
| `⌘+K`                                     | Toggle software keyboard                                                                   |
| `⌘+1 / 2 / 3`                             | Resize simulator window                                                                    |
| `Device → Erase All Content and Settings` | Reset simulator (use this to simulate a fresh install when testing Plan 2's per-user data) |


### Manual test pass — Plan 3 (Auth Bootstrap)

1. **Cold launch, no session**: Erase the simulator. Launch app → should see splash → Welcome → Sign Up.
2. **New sign-up**: Welcome → Sign Up → fill onboarding → submit → see "Done" celebration → tap Continue → lands in `MainTabView` with empty Home and empty Community.
3. **Cold launch with valid session**: Kill the app (swipe up in app switcher). Launch again → splash briefly → straight into `MainTabView` (no re-login).
4. **Sign out**: Profile → "Sign Out" → back to Welcome.
5. **Existing user, onboarding incomplete**: in Supabase Studio, set a test user's `onboarding_completed_at` to NULL. Sign in as them → should jump directly to the College step.

### Manual test pass — Plan 2 (Per-user data)

1. **User A fresh install**: Erase simulator → sign up A → see zero bubbles + zero notes → tap "Add Course" → create "CS101" → write a note → sign out.
2. **User B same device**: Sign up B → should see zero bubbles + zero notes (NOT A's CS101) → create "MATH202" → sign out.
3. **Switch back to A**: Sign in as A → should see CS101 + the note, NOT MATH202.

### Manual test pass — Plan 1 (Community)

This needs two test users — easiest is two simulators side by side, or simulator + real iPad. To run two simulators: `Xcode → Open Developer Tool → Simulator`, then `File → Open Simulator → iPad Pro (M4) – second instance`.

1. **A creates a post with a PDF + 2 hashtags**:
  - Sign in as A → Community tab → tap "Start a new post…" card.
  - Enter title + body.
  - Tap "Attach PDF" → pick a PDF from the Files app (drag any PDF into the simulator first, or use Safari to download one).
  - Type a hashtag → autocomplete dropdown appears after a moment.
  - Tap Publish → post appears at top of feed.
2. **B sees A's post**: Sign in as B in the second simulator → Community tab → A's post should appear in the feed.
3. **B likes it**: Tap the heart → fills in instantly (optimistic), count goes up.
4. **A refreshes**: Pull-to-refresh on A's feed → A sees `likesCount = 1`, `hasLiked = false`.
5. **Threaded comments**: B taps A's post → comment "Great notes!" → A taps **Reply** on that comment → "Thanks!" — both see the thread.
6. **Hashtag filter**: A taps a hashtag chip on their own post → feed shows only posts with that tag → tap the "✕" on the active-filter pill → back to public feed.
7. **PDF viewer**: A taps the PDF attachment on B's post → QuickLook opens the PDF.
8. **Delete**: A taps the trash icon on their own post → confirm → post disappears. B pulls-to-refresh → it's gone for them too.

### Inspect network / console logs

- Xcode bottom panel → **Debug Area** (`⌘+Shift+Y`) → shows `print()` output and crashes.
- For deeper network inspection, use Charles or Proxyman.

---

## Level 3 — Real iPad (closest to production, slower iteration)

**Good for:** Apple Pencil, real performance, real network, real file picker, real keyboard. Required before TestFlight.

### One-time setup

1. Connect iPad via USB-C cable.
2. On the iPad: `Settings → Privacy & Security` → scroll to the bottom → enable **Developer Mode** (you'll need to restart the iPad).
3. After Xcode runs your build for the first time, on the iPad go to `Settings → General → VPN & Device Management` → trust your developer profile.
4. In Xcode: `Window → Devices and Simulators` → select your iPad → it should show as ready.

### Wireless deploy (optional but nice)

1. With the iPad connected by cable, in `Window → Devices and Simulators`, check **"Connect via network"**.
2. Unplug — iPad now shows up wirelessly as long as it's on the same Wi-Fi.

### Run on iPad

1. In the device dropdown in Xcode, pick your iPad's name.
2. Press `⌘+R`.
3. First build to a real device takes ~1 minute. Subsequent builds are fast.
4. On iPad: if you see "Untrusted Developer", complete step 3 of one-time setup.

### What to specifically re-test on a real iPad

- **Apple Pencil**: open a note → draw → strokes should be smooth, no lag.
- **PDF export**: write a note → confirm it saves locally → Library shows it.
- **PDF upload to Community**: attach a PDF → Publish → confirm it appears on another device.
- **Keyboard handling**: text fields shouldn't be hidden under the keyboard.
- **OAuth (Google / Apple)**: only properly testable on a real device because of redirect URL handling.

---

## Level 4 — TestFlight (share with other testers, closest to App Store)

**Good for:** Inviting other people (your two test users on different physical devices), final pre-launch check.

### Prerequisites

1. **Paid Apple Developer Program account** ($99/year). TestFlight does NOT work with a free personal team.
2. Your team set in `Signing & Capabilities` must be your **paid** team.
3. Bump the build number every upload: `Noteworks target → General → Identity → Build` (e.g. `1 → 2 → 3 ...`). Version (`1.0.0`) only changes when shipping to App Store.

### Upload steps

1. In Xcode, top device dropdown → pick **"Any iOS Device (arm64)"** (this is the archive target).
2. `Product → Archive` (no shortcut, but it's in the Product menu).
3. Wait ~3–5 minutes for Xcode to build a release archive.
4. The **Organizer** window opens when done. Pick the new archive → **Distribute App → App Store Connect → Upload**.
5. Xcode signs and uploads (~5 more minutes).
6. Go to [App Store Connect](https://appstoreconnect.apple.com/) → **My Apps → Noteworks → TestFlight**.
7. New build appears as "Processing" for ~10–20 minutes, then "Missing Compliance".
8. Click the build → answer the encryption question (almost always "No, my app does not use encryption" *unless you're doing something exotic* — Supabase uses HTTPS which is exempt).
9. Add **Internal Testers** (you, anyone with App Store Connect access) — they get the build immediately.
10. For **External Testers**, you need a one-time Apple review (~1 day for the first build, instant after that). Add email addresses → they get an invite to install the TestFlight app and your build.

### What testers do

1. Install the **TestFlight** app from the App Store on their iPad/iPhone.
2. Tap your invite link → see Noteworks → tap **Install**.
3. Open Noteworks like a normal app.
4. To send feedback: in TestFlight, tap the app → **Send Beta Feedback** → screenshot + text. You see it in App Store Connect.

### Watching crashes from TestFlight

- App Store Connect → **TestFlight → Crashes** for crash reports.
- Xcode → **Organizer → Crashes** to symbolicate them locally.

---

## Recommended flow when working on a feature

Most productive iteration loop:

1. **Previews** while shaping the layout (`⌘+Option+P`).
2. **Simulator** for everything that touches data or networking (`⌘+R`).
3. **Two simulators** when testing user-to-user community flows.
4. **Real iPad** once before each meaningful merge — catches Pencil, real-keyboard, and OAuth-redirect bugs.
5. **TestFlight** once a week (or before any external demo) for end-to-end validation on someone else's device.

---

## Quick troubleshooting


| Symptom                                             | Fix                                                                                                             |
| --------------------------------------------------- | --------------------------------------------------------------------------------------------------------------- |
| "Could not launch Noteworks" on iPad                | Trust developer profile in `Settings → General → VPN & Device Management`                                       |
| "Untrusted Developer" on simulator                  | Reset simulator: `Device → Erase All Content and Settings`                                                      |
| Sign-in works but Community is empty for everyone   | Open Xcode console — usually a 401 because the access token is missing; sign out + sign in again                |
| Hashtag autocomplete never shows results            | Your test account needs to exist in `auth.users` — sign in fresh; hashtags only work on signed-in calls         |
| PDF picker doesn't open                             | Make sure you tapped the "Attach PDF" button itself, not the row below it (rows below are uploaded attachments) |
| "Build number must be greater" on TestFlight upload | Increment `Build` field in `Noteworks → General → Identity`                                                     |


