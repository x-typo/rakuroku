# Copilot Code Review Instructions

This is a native iOS app (SwiftUI) for anime and manga tracking via AniList.
The TypeScript/React Native codebase is being phased out. All new code must be Swift.
Flag violations of these conventions during review.

## Migration Rule

- All new features and fixes go in `Rakuroku/Rakuroku/` (SwiftUI). Never in `src/` (TypeScript).
- Do not add new npm dependencies or modify `package.json` for app features.
- Flag any PR that adds TypeScript code to the app (test/CI config changes are OK).

## Architecture

- **MVVM-inspired**: Views bind to `@Observable` stores, services handle I/O.
- Models are structs with computed properties. No side effects in models.
- All GraphQL queries live in static `Queries` enum, mutations in `Mutations` enum inside `AniListClient`. Never inline query strings in views or stores.
- Type definitions for API responses are defined inline near the query that uses them, inside the client methods.

## Concurrency

- `AniListClient` is an actor (singleton via `.shared`). Flag if changed to a class.
- All network calls use async/await. No completion handlers.
- `@MainActor` required on stores and services that update UI state (`AuthStore`, `AnimeKaiStore`).
- OAuth flow uses `withCheckedThrowingContinuation` for bridging `ASWebAuthenticationSession`. Continuation must resume exactly once.
- Pagination loops must respect task cancellation.

## Error Handling

- Custom `AniListError` enum conforming to `LocalizedError`.
- HTTP 429 (rate limit) must be detected and surfaced, not silently retried.
- Graceful fallback: if token-authenticated request fails with auth error, retry without token before surfacing error.
- Views display errors via state-driven `ContentStateViews` (loading/error/empty patterns).
- Adult content filtered by default (`isAdult != true`). Flag any query missing this filter.

## State Management

- Use `@Observable` macro for stores. Not `ObservableObject`, not `@EnvironmentObject`.
- Stores injected via `.environment()` at app root.
- `@State` for transient view-local state only.
- OAuth tokens stored in Keychain via `KeychainHelper`. Never in UserDefaults.
- Username stored in UserDefaults (non-sensitive).

## Security

- Tokens in Keychain only. Flag any token written to UserDefaults or files.
- Custom URL scheme (`rakuroku://`) validated before processing callbacks.
- No hardcoded client IDs in source.

## SwiftUI Patterns

- Per-tab `NavigationStack` with shared destination types (`MediaDetailDestination`, `StudioDestination`, `SeasonListDestination`).
- Swipe gestures on `MediaCardView` for progress updates (left: -1, right: +1). Progress must not exceed total episodes/chapters.
- Pull-to-refresh on all list views.
- `AsyncCoverImage` for remote images. No inline `AsyncImage` with custom placeholder logic.
- `FilterSheet` for status filtering. Filter state lives in the parent view, not the sheet.

## Theming

- All colors from `Theme` enum in `Constants/Theme.swift`. No hardcoded color literals.
- Dark theme only. No light mode support. Flag any `colorScheme` conditionals.
- Status colors: watching = green, completed = blue, dropped = red, paused = yellow, planning = gray.

## Testing

- Swift Testing framework (`@Suite`, `@Test`, `#expect`) for new tests.
- Test pure functions: model computed properties, formatting, parsing.
- AnimeKai resolver HTML parsing is a priority test target.
- No mocking framework needed. Test with real domain objects.

## Naming

- Types: PascalCase (`AniListClient`, `MediaCardView`, `AuthStore`).
- Functions/properties: camelCase.
- Views end with `View` suffix. Stores end with `Store` or `Client`.
- File names match the primary type.
- `// MARK: -` for section organization within files.

## Performance

- `LazyVStack` for scrollable lists. Not `VStack` with `ForEach`.
- Pagination: fetch next page on scroll near bottom. Cap at 20 pages for large datasets.
- AnimeKai resolved paths cached in `AnimeKaiStore` (UserDefaults). Flag redundant lookups.
- `@discardableResult` for fire-and-forget mutations (e.g., progress updates).
