# Rakuroku

A personal anime and manga tracking app built with SwiftUI, integrating with the AniList API.

## About

Rakuroku was developed as both a personal utility for tracking anime/manga consumption and a learning project to explore native iOS development with SwiftUI. The app demonstrates real-world implementation of OAuth authentication, GraphQL API integration, and SwiftUI best practices.

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
| **Swift**               | Language                                |
| **SwiftUI**             | UI framework                            |
| **AniList GraphQL API** | Data source for anime/manga information |
| **Keychain Services**   | Secure token storage                    |

## Project Structure

```
Rakuroku/Rakuroku/
  Constants/     # Theme, colors
  Models/        # AniList data models, GraphQL payloads
  Services/      # API client, auth, AnimeKai resolver, Reddit discussions
  Utilities/     # Formatters, error helpers
  Views/         # SwiftUI views (screens + components)
    Components/  # Reusable UI (MediaCard, SearchBar, FilterSheet, etc.)
  RakurokuApp.swift  # App entry point
```

## Setup

1. Clone the repository
2. Open `Rakuroku/Rakuroku.xcodeproj` in Xcode
3. Select your development team under Signing & Capabilities
4. Build and run on a simulator or device

### AniList OAuth Configuration

To enable authenticated features (progress updates, score/status changes):

1. Create an API client at [AniList Developer Settings](https://anilist.co/settings/developer)
2. Set the redirect URL to `rakuroku://auth`
3. If OAuth is blocked, use **Profile > Paste Access Token**

### External Watch Provider (AnimeKai)

- The app calculates the next episode to watch from your AniList progress and opens it in your system browser.
- If the show can't be resolved automatically, you can pick from candidates, paste an override link, or open AnimeKai home.
- The app does not auto-update AniList progress after playback.

## Acknowledgments

- [AniList](https://anilist.co) for providing the API
