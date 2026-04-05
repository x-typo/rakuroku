# Rakuroku Agent Notes

This file contains repo-local instructions for AI coding agents.

## Scope

- Repo root: `rakuroku/` (this directory)
- Xcode project: `Rakuroku/Rakuroku.xcodeproj`
- Language: Swift (SwiftUI)
- No package manager (no SPM dependencies currently)

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

## AnimeKai Watch Integration

- Resolver: `Rakuroku/Rakuroku/Services/AnimeKaiResolver.swift` resolves an AnimeKai watch path by searching and verifying the AniList ID.
- Do not implement "Cloudflare bypass" behavior; keep this feature as safe linking + user-visible fallbacks only.
