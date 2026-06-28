# Rakuroku Agent Notes

This file contains repo-local instructions for AI coding agents.

## Scope

- Repo root: `rakuroku/` (this directory)
- Xcode project: `Rakuroku/Rakuroku.xcodeproj`
- Language: Swift (SwiftUI)
- Minimum deployment target: iOS 18.0
- No package manager (no SPM dependencies currently)
- App source lives under `Rakuroku/Rakuroku/`
- Do not add TypeScript, React Native, npm, or `package.json` app work; this repo has moved to native SwiftUI.

## Agent Guidance

- This file is the canonical repo-local AI guidance. Fold old Copilot or Claude-specific notes into this file instead of recreating separate agent instruction files.
- Follow the existing SwiftUI patterns before adding new architecture.
- Do not edit `project.pbxproj` by hand unless a project setting must change; keep those edits minimal and verify with `xcodebuild`.

## Architecture

- App-wide state lives in `@Observable` stores such as `AuthStore` and `AnikotoTVStore`.
- Inject stores with `.environment()` at the app root; do not switch to `ObservableObject` or `@EnvironmentObject`.
- Screen-local state should use `@State`.
- `AniListClient` is an actor singleton via `.shared`; keep network calls on async/await.
- Models are structs with computed properties and no side effects.
- Views end with `View`, stores end with `Store`, and clients end with `Client`.
- Use `// MARK: -` for meaningful section organization inside larger Swift files.

## AniList API

- All GraphQL queries live in `private enum Queries` in `Rakuroku/Rakuroku/Services/AniListClient.swift`.
- All GraphQL mutations live in `private enum Mutations` in `Rakuroku/Rakuroku/Services/AniListClient.swift`.
- Response types may be local to the client method unless shared by multiple methods.
- Detect HTTP 429 and surface rate limiting instead of silently retrying.
- If a token-authenticated read fails with an auth error, fall back to the public read before surfacing the error when that behavior matches the existing client pattern.
- Filter adult media client-side after decoding with `.filter { $0.isAdult != true }` on new media-returning queries.
- Pagination loops should include cancellation checks where practical and stay capped for large datasets.

## Build (Physical Device)

Discover device ID dynamically, then build and install:

```bash
cd /Users/x-typo/Documents/GitHub/rakuroku
DEVICE_ID=$(xcodebuild -project Rakuroku/Rakuroku.xcodeproj -scheme Rakuroku -showdestinations 2>&1 | grep "name:Ty's iPhone" | sed 's/.*id:\([^,}]*\).*/\1/')

# Build
xcodebuild -project Rakuroku/Rakuroku.xcodeproj -configuration Release -scheme Rakuroku -destination "id=$DEVICE_ID" -allowProvisioningUpdates

# Install
xcrun devicectl device install app --device "$DEVICE_ID" "$(find ~/Library/Developer/Xcode/DerivedData/Rakuroku-*/Build/Products/Release-iphoneos/Rakuroku.app -maxdepth 0 -print -quit)"
```

## AniList OAuth

- Redirect URI: `rakuroku://auth`
- OAuth uses `ASWebAuthenticationSession` with `.customScheme("rakuroku")`.
- The callback handler must validate the callback shape, fragment, and OAuth state before storing tokens.
- OAuth tokens must only be stored in Keychain via `KeychainHelper`; never store tokens in UserDefaults or files.
- Username may be stored in UserDefaults because it is not sensitive.
- Public OAuth client IDs may be hardcoded; do not hardcode client secrets, API keys, or tokens.

## SwiftUI UI Patterns

- Each tab has its own `NavigationStack` with shared destination types (`MediaDetailDestination`, `StudioDestination`, `SeasonListDestination`).
- Use `ContentLoadingView` and `ContentErrorView` from `ContentStateViews.swift` for list screen loading and error states.
- All data screens need loading, error, and empty states.
- Use `AsyncCoverImage` for cover art and thumbnails. Inline `AsyncImage` is fine for one-off images such as detail banners.
- Use `FilterSheet` for status filtering; filter state belongs in the parent view.
- Use app colors from `Theme` in `Constants/Theme.swift`; the app is dark theme only.
- `MediaCardView` swipe progress updates must not exceed total episodes or chapters.

## External Watch Integration

- Resolver: `Rakuroku/Rakuroku/Services/AnikotoTVResolver.swift` searches AnikotoTV for the AniList title and extracts the real watch path.
- Do not implement "Cloudflare bypass" behavior; keep this feature as safe linking + user-visible fallbacks only.
- Cache resolved AnikotoTV watch paths in `AnikotoTVStore` to avoid redundant searches.

## Testing Direction

- There is no test target yet.
- Prefer Swift Testing (`@Suite`, `@Test`, `#expect`) if a test target is added.
- Prioritize pure functions first: formatters, model computed properties, and `AnikotoTVResolver` parsing.
- No mocking framework is needed for the first test target; use real domain objects.
