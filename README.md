# OpenFlix — Flutter (Android-first)

An open, modular media aggregator built on the Stremio Addon Protocol v3. This milestone covers the Home screen, the app icon, and live catalogs from the **Xperience** addon.

## Run

```bash
# 1. Create the platform shells around this lib/ folder
flutter create --org com.pixel --platforms android .
# 2. Install deps
flutter pub get
# 3. (optional) App icon: export Figma frame 32:15 to assets/app_icon.png
#    and the foreground layer to assets/app_icon_foreground.png
mkdir -p assets && dart run flutter_launcher_icons
# 4. Native splash (kills the white launch screen — run once)
dart run flutter_native_splash:create
# 5. Check the project, then test performance in release mode on a device.
flutter analyze
flutter test
flutter run --release
flutter build apk --release --split-per-abi # smallest APKs per CPU
```

Add `<uses-permission android:name="android.permission.INTERNET"/>` and `<uses-permission android:name="android.permission.VIBRATE"/>` to `android/app/src/main/AndroidManifest.xml`.

### If Gradle's daemon disappears

This is a **host-side Gradle process exit**, not a Dart compiler diagnostic or
an Android-device RAM issue. Check `flutter analyze` and `flutter test` first.
If those pass, inspect `free -h`, `df -h`, and the daemon log named in the build
output. An abrupt log ending **may** mean the Linux OOM killer terminated it;
confirm with `journalctl -k -b | grep -Ei 'oom|killed process'` (or `dmesg`).

If memory pressure is confirmed, change the existing values in the generated
`android/gradle.properties` (keep only one of each property):

```properties
org.gradle.jvmargs=-Xmx2g -XX:MaxMetaspaceSize=512m -Dfile.encoding=UTF-8
org.gradle.workers.max=2
org.gradle.parallel=false
```

Then run `cd android && ./gradlew --stop && cd ..` before retrying
`flutter run --release`. If no OOM appears, keep the complete daemon log and
retry with `flutter run --release -v` instead of guessing the cause.

## Architecture

```
lib/
├── core/{constants,network,theme,perf}
├── features/
│   ├── home/
│   │   ├── data/{models,repositories}
│   │   ├── domain/repositories
│   │   └── presentation/{controllers,widgets,screens}
│   └── details/
│       ├── data
│       └── presentation/{screens,widgets}
└── main.dart
```

## Original Portrait Layout

Only the original Xperience addon is configured in `ApiConstants.xperienceManifestUrl`.
The repository reads that manifest directly and preserves its catalog order.
Catalogs use their original `type/id` keys; there is no addon-merging or alternate
row-layout logic.

Home shelves and the details screen share the original 113x170 portrait cards,
8px poster gaps, 7px corner radius, and snap scrolling.
Under the details screen's "Related" tab, two OTT rows are provided:
1. **"More Like This"** — powered by TMDB's `/movie/{id}/similar` endpoint.
2. **"Viewers Also Watched"** — powered by TMDB's `/movie/{id}/recommendations` endpoint.
Both rows display all titles returned by TMDB (not limited to 12), sorted
with the most popular appearing first, and styled with Better Posters (btttr.cc)
artwork: `https://btttr.cc/poster-a/imdb/poster-default/{imdb_id}.jpg`.

The Home, Movies, TV Shows, Anime, and Categories navigation, details screens,
tab selection indicator, TMDB hero artwork, and Better Posters related posters
remain in place. The hero and details backdrops are not catalog rows and are
unchanged by this rollback.

- **Flow:** manifest -> base URL (strip `/manifest.json`) -> first 3 catalogs concurrently -> remaining shelves load lazily -> parse `{metas: [...]}`.
- **States:** `HomeInitial`, `HomeLoading` (skeleton), `HomeReady`, `HomeError` (with a retry button).
- **Resilience:** Dio retries with backoff (timeouts, 5xx, 429). Images fall back from `poster` to `posterFallback` to a title card. Pull-to-refresh is supported.

## Performance notes (tuned for ~3GB RAM devices)

1. **Release mode matters.** Debug and release performance differ. Measure startup and scroll frames with a release or profile build on the target device; build mode alone does not diagnose a long startup delay.
2. **Image bytes are bucketed.** TMDB URLs (`original`/`w500`) are rewritten to the size actually used (w342 for 113px cards, w780 for the hero) — several MB less download/decode per image.
3. **Decoded-image RAM is capped.** `PaintingBinding.imageCache` is limited to 48 MiB/120 entries; every `CachedNetworkImage` gets `memCacheWidth/Height` so decode happens at display size.
4. **Disk cache.** A 30-day `flutter_cache_manager` store (350 objects) means repeat launches don't re-download posters.
5. **Rebuild isolation.** Shelf state lives in a `Map<key, ShelfState>`; each row `select`s only its own entry, so one shelf loading never rebuilds others. `keepAlive` rows aren't re-fetched after scrolling off-screen.
6. **Prefetch.** After the hero + first shelves resolve, the next hero slides and first posters are pre-warmed into cache.
7. **Scroll:** `cacheExtent: 600` on the vertical list decodes one row ahead of the viewport.
8. **Poster-snap rails.** Horizontal rows use `PosterSnapPhysics` + a fixed `itemExtent` (121px): flings travel naturally but always land on a poster boundary (no half-cut cards), and fixed-extent layout skips per-child measuring entirely.
9. **No animated placeholders.** Loading posters show a flat dark tile instead of a shimmer — during a fling a shimmer per poster means dozens of live animations. Shimmer remains only in the one-time startup skeleton.
10. **Background JSON parsing.** Dio's `BackgroundTransformer` decodes catalog payloads (100+ metas) on a separate isolate, so parsing never drops frames.
11. **Black native splash.** `flutter_native_splash` paints the OS launch window black — no white flash while the engine boots. First-paint happens right after the ~5KB manifest; shelves stream in afterwards.
