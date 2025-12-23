# Rakuroku (楽録)

> "Enjoyable Recording" - An anime tracker app

## Tech Stack
- React Native (cross-platform framework)
- TypeScript
- Apollo Client (GraphQL client)
- AniList GraphQL API (https://graphql.anilist.co)

## Key Resources
- AniList API docs: https://docs.anilist.co
- AniList GraphiQL explorer: https://anilist.co/graphiql
- Apollo Client docs: https://www.apollographql.com/docs/react/
- React Native docs: https://reactnative.dev/docs/getting-started
- Reference app (AniHyou): https://github.com/axiel7/AniHyou-android

## Core Features (MVP)
1. OAuth login with AniList account
2. Display user's watching list
3. Airing schedule with countdown timers for next episodes
4. Filter schedule by shows on my list only

## Milestones
- [x] Environment setup (React Native, Xcode, Android Studio)
- [x] Basic app scaffold with navigation
- [ ] Apollo Client configured with AniList endpoint
- [ ] Fetch and display anime list (no auth)
- [ ] OAuth implementation
- [ ] Airing schedule view
- [ ] Desktop support

## Preferences
- Keep code clean and typed (TypeScript strict mode)
- Prefer functional components with hooks
- Minimal dependencies where possible
- Explain GraphQL concepts when introducing new query patterns

## Current Status
Environment set up. Basic navigation working. Next: Apollo Client setup.
