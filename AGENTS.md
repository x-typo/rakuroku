# Rakuroku Agent Notes

This file contains repo-local instructions for AI coding agents.

## Scope

- Repo root: `rakuroku/` (this directory)
- Package manager: `npm` (commit changes to `package-lock.json`)
- Native folders: `ios/` and `android/` are generated and are ignored by git in this repo

## Commands

- Dev: `npm start`
- Lint: `npm run lint`
- Typecheck: `npm run typecheck`
- Test: `npm test`
- Web export: `npx expo export -p web`
- iOS export: `npx expo export -p ios`

## iOS Release Mode (Physical Device)

Build a standalone app (no dev server required at runtime):

- `npx expo run:ios --device "00008130-00113998046B8D3A" --configuration Release`

If `expo run:ios` hangs while installing to a physical device, use Apple tooling:

- Install: `xcrun devicectl device install app --device 00008130-00113998046B8D3A <path-to-Rakuroku.app>`
- Launch: `xcrun devicectl device process launch --device 00008130-00113998046B8D3A com.rakuroku.app`

## AniList OAuth

- Redirect URI (standalone/dev build): `rakuroku://auth`
- In Expo Go, the redirect URI is computed by `expo-auth-session` and typically ends with `/--/auth`

## AnimeKai Watch Integration

- Resolver: `src/providers/animekai.ts` resolves an AnimeKai `/watch/<slug>` path by searching and verifying the AniList ID in the HTML.
- UI: `src/screens/MediaDetail.tsx` opens the next-episode URL in a real browser session (`expo-web-browser`).
- Do not implement "Cloudflare bypass" behavior; keep this feature as safe linking + user-visible fallbacks only.

