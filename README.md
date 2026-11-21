# OpenFlix

An open-source Android media streaming client engineered for a cinema-grade OLED UI, smooth 60fps performance on 3GB RAM devices, 1-click TMDB sync, and Stremio/CloudStream addon playback.

## Highlights
- **OLED-Black Cinema UI:** Custom poster-by-poster carousel snapping, responsive scaling, and minimal clutter.
- **High-Performance Playback:** Powered by `media_kit` (`libmpv`) with an in-player **Links** switcher, Skip Intro, and Play Next.
- **1-Click TMDB Sync:** Watchlists, liked titles, curated franchises, and your custom TMDB lists out of the box.
- **Built for Constrained Hardware:** Tuned image caching and memory limits for 3GB RAM Android phones.
- **Built-In Update Checker:** Checks GitHub Releases automatically and grabs the right APK for your CPU.

## Download (Android)
Grab the latest signed APK from [**Releases**](https://github.com/Husnain-code-byte/OpenFlix/releases/latest):
- **`OpenFlix-v1.0.0-arm64-v8a.apk`** — Recommended for almost all modern Android phones (~78 MB).
- **`OpenFlix-v1.0.0-universal.apk`** — Use if you're unsure of your device's architecture (~118 MB).

## Community & Support
- **Discord:** [Join the OpenFlix Server](https://discord.gg/y5QssSBcpJ) for setup help, bug reports, and feature requests.

## Building from Source
1. Create `.env.prod.json` in the project root:
   ```json
   { "TMDB_API_KEY": "your_tmdb_v3_api_key" }
   ```
2. Build the release APK:
   ```bash
   flutter pub get
   flutter build apk --release --target-platform android-arm64 --dart-define-from-file=.env.prod.json
   ```

## Disclaimer
OpenFlix is a media client and metadata browser. It does not host, provide, or distribute any media content. Users are solely responsible for any third-party addons they configure.
