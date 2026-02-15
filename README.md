# Rakuroku

A personal anime and manga tracking app built with React Native and Expo, integrating with the AniList API.

## About

Rakuroku was developed as both a personal utility for tracking anime/manga consumption and a learning project to explore modern mobile development practices. The app demonstrates real-world implementation of OAuth authentication, GraphQL API integration, and React Native best practices.

## Features

- **Anime & Manga Lists** - View and filter your AniList library by status (Watching, Completed, Dropped, Planning)
- **Airing Schedule** - Track daily anime releases with swipe navigation between days
- **Seasonal Discovery** - Browse current and upcoming season anime sorted by popularity
- **Search** - Search the entire AniList database
- **Media Details** - View comprehensive information including synopsis, relations, rankings, and studio details
- **Progress Tracking** - Increment episode/chapter progress directly from the app
- **Watch Next Episode (External)** - Open the next episode in your browser based on your AniList progress (AnimeKai provider with manual override + fallbacks)
- **Score & Status Management** - Update ratings and watch status via intuitive modals
- **OAuth Authentication** - Secure sign-in with AniList to sync changes to your account
- **Pull-to-Refresh** - Refresh data across all screens

## Tech Stack

| Technology              | Purpose                                 |
| ----------------------- | --------------------------------------- |
| **React Native**        | Cross-platform mobile framework         |
| **Expo (~54.0)**        | Development toolchain and build system  |
| **TypeScript**          | Type-safe development with strict mode  |
| **AniList GraphQL API** | Data source for anime/manga information |
| **expo-auth-session**   | OAuth 2.0 implicit flow authentication  |
| **expo-secure-store**   | Secure token storage                    |
| **React Navigation**    | Tab and stack navigation                |
| **Jest (jest-expo)**    | Unit tests                              |
| **ESLint**              | Linting                                 |

## Learning Outcomes

This project provided hands-on experience with:

- **GraphQL** - Writing queries and mutations for a production API
- **OAuth 2.0** - Implementing implicit flow for mobile apps without a backend
- **React Native Patterns** - FlatList optimization, custom hooks, context providers
- **TypeScript** - Strict typing for API responses and component props
- **State Management** - Local state with hooks, optimistic UI updates
- **Mobile UX** - Gesture navigation, pull-to-refresh, modal interactions

## Project Structure

```
src/
  api/           # AniList GraphQL queries and mutations
  components/    # Reusable UI components
  constants/     # Colors, filter options
  context/       # Authentication context provider
  providers/     # External watch providers (AnimeKai)
  hooks/         # Custom hooks (useMediaList)
  screens/       # Screen components
  types/         # TypeScript type definitions
```

## Setup

1. Clone the repository
2. Install dependencies:
   ```bash
   npm install
   ```
3. Create a `.env` file with your AniList credentials:
   ```
   EXPO_PUBLIC_ANILIST_USERNAME=your_username
   EXPO_PUBLIC_ANILIST_CLIENT_ID=your_client_id
   ```
4. Start the development server:
   ```bash
   npm start
   ```

### AniList OAuth Configuration

To enable authenticated features (progress updates, score/status changes):

1. Create an API client at [AniList Developer Settings](https://anilist.co/settings/developer)
2. Set the redirect URL based on your environment:
   - **Standalone / dev build**: `rakuroku://auth`
   - **Expo Go**: use the value logged by the app (look for `[Auth] redirectUri=...` in Metro logs)
3. Add the Client ID to your `.env` file
4. If OAuth is blocked (or redirect URLs are hard to line up), use **Profile → Paste Access Token**

### External Watch Provider (AnimeKai)

- The app calculates the next episode to watch from your AniList progress and opens it in your system browser.
- If the show can’t be resolved automatically, you can pick from candidates, paste an override link, or open AnimeKai home.
- The app does not auto-update AniList progress after playback.

## Scripts

```bash
npm start        # Start Expo dev server
npm run web      # Run in a web browser
npm run ios      # Run on iOS simulator/device
npm run android  # Run on Android emulator/device

npm run lint      # ESLint
npm run typecheck # TypeScript (no emit)
npm test          # Jest
npm run test:watch # Jest watch mode
```

## Release Mode (Physical Device)

Build a standalone app that works without Metro at runtime:

```bash
npx expo run:ios --device "<DEVICE_UDID>" --configuration Release
```

If `expo run:ios` hangs while installing to a physical device, you can install/launch with Apple tooling:

```bash
xcrun devicectl device install app --device <DEVICE_UDID> ~/Library/Developer/Xcode/DerivedData/Rakuroku-*/Build/Products/Release-iphoneos/Rakuroku.app
xcrun devicectl device process launch --device <DEVICE_UDID> com.rakuroku.app
```

## Acknowledgments

- [AniList](https://anilist.co) for providing the API
