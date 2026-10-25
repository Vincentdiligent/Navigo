# Navigo

![Release APK](https://github.com/Vincentdiligent/Navigo/actions/workflows/release.yml/badge.svg)

Premium navigator for Android: MapLibre vector cartography with two
from-scratch map themes (Atlas by day, Onyx by night), turn-by-turn voice
guidance that works offline, downloadable offline regions for 56 countries,
saved places, route planning across several backends, speed-limit and
speed-camera ("радары") assist for the car, and public transport lines.
No API keys, no accounts, no paid services — every data source below is
open and keyless.

Current build: **6.9.0**. Everything under this line is the release
changelog, newest headline first.

**v6.5 is the TRUE CARTOGRAPHY release:
two completely new map themes — Atlas (light) and Onyx (dark) — complete
from-scratch documents in the spirit of Apple Maps (own road hierarchy,
own label ladder, own POI system of colored chips with category glyphs —
white chips on light, charcoal chips at night), NOT recolors of the old
cartography; plus the real anti-flicker fix: the map now FADES IN — an
opaque cover masks the platform view's whole lifecycle (creation frame,
style swap, wake rebuild) and melts away once the style and the first
tiles have landed.**

- **Two mega-premium cartographies that share nothing with the old
  looks.** The user: «я не просил сделать премиум темы сменив цвет! …
  сделай две именно совершенно другие! отрисовка poi, тайлы — совершенно
  другой стиль! … максимально похоже как apple map». v6.5 ships exactly
  that, built on research (measured Apple Maps palettes from the live
  web renderer + the MIT reference cartography of
  github.com/dddevid/MapLibre-GL-JS-AppleMaps-Style) on the SAME keyless
  OpenFreeMap tiles:
  - **Atlas** — warm paper land `#F2F2F7`, bright water `#A8D4F0`,
    cream-yellow motorways, casing-first clean roads, rail with
    hatching, dashed footpaths, soft park greens, Inter-class typography
    (Noto Sans on OpenFreeMap glyphs) with sentence-case labels;
  - **Onyx** — the night twin: `#1C1C1E` land, deep `#0D2535` water,
    dark amber motorways, buildings a step lighter than the land;
  - **POI chips** (`lib/map/poi_chips.dart`) — 25 canvas-drawn circular
    badges in the Apple category colors (food orange, shopping pink,
    health red, transit/civic/education blue, leisure green, arts
    purple, hotels teal, landmarks brown) — white chips + saturated
    glyphs in Atlas, charcoal chips + muted glyphs in Onyx; registered
    at style load via `addImage`, no assets, no sprite sheets, no keys;
  - the documents are INLINE constants (`lib/map/apple_docs.dart`) —
    no style fetch, instant boot, probe/watchdog untouched;
  - Navigo rules baked in: flat buildings uncapped (v5.4), generalized
    grass/wood clamped away from city centers (v6.4 «Bordeaux rule»),
    gate noise filtered out of the POI layer;
  - the retired v6.4 paint-rewrites (Porcelain/Obsidian) took exactly
    these two slots — saved theme indices keep their meaning.
- **The map fades in instead of flashing.** The user: «мерцание
  осталось… Настоящее лечение мелькания — не смена рендера, а
  маскирование жизненного цикла поверхности». v6.5: an opaque scrim in
  the ACTIVE THEME's own land color covers the map at every lifecycle
  edge (app start, wake rebuild, theme switch, watchdog fallback) and
  fades out ~160 ms after the style lands, over 340 ms — the map
  «проявляется» without a single flash. Renderer-independent: it works
  for the fast SurfaceView AND for the experimental TextureView toggle
  (Settings → «Новый рендер карты»), which stays opt-in because it
  freezes scrolling on some devices.
- **Voice guidance is FIXED — the true root cause.** The user: «Голосовые
  подсказки не работают исправь както? есть возможность?». Yes, there was
  one, and it was hiding in the manifest: on Android 11+ `TextToSpeech`
  must bind to a THIRD-PARTY TTS engine app (Google TTS etc.), and package
  visibility silently blocks that binding unless the app declares the
  `android.intent.action.TTS_SERVICE` intent in `<queries>`. v6.1 and
  everything before never declared it — the speech engine was simply dead
  on modern Android, no matter how correct the Dart code was. v6.2:
  - the documented `<queries>` intent is in the merged manifest;
  - `NavVoice` is hardened: languages are tried as full BCP-47 codes
    (ru-RU → ru → en-US → en), each init step fails independently, so one
    broken setter can no longer disable the whole voice;
  - the sound toggle (nav top bar + settings) now REALLY rules the
    speaker through an `enabled` gate — the old toggle flipped a flag
    nobody read;
  - Настройки → Навигация → **«Проверить голос»** — one tap proves the
    engine speaks (and reports «движок недоступен» when it truly can't).
- **Every tap opens the card INSTANTLY.** The user: «тапаю по местам раз
  10 тапал по разным местам получил либо блок либо баг потому что тап уже
  не открывал меню нигде… я ждал минуту и окно после долгой паузы само
  открылось как будто таймаут был тапов». Root cause: the tap flow
  AWAITED network (reverse geocode 12 s, building OSM tags) while holding
  the tap guard — one throttled Nominatim request froze EVERY tap for up
  to a minute. v6.2:
  - the card opens immediately on local tile data (POI name / building
    footprint + tile height / «Выбранная точка» + coordinates);
  - the network lands progressively INSIDE the card: the address and the
    real OSM name arrive when Nominatim answers, floors/height of a
    building arrive when Overpass answers, a nameless pin/building gets
    its strict Wikipedia pass after the name is revealed (monuments
    tapped as footprints keep their wiki card);
  - the tap guard now only covers the millisecond platform-channel picks;
  - the long-press menu reverse-geocode is capped at 4 s;
  - all Nominatim calls go through a serial 1-req/s gate with a session
    cache — rapid multi-tapping can no longer trip the usage policy.
- **The photo carousel cannot flash and collapse anymore.** The user:
  «википедия и фото всплывают в одно время… сверху макет фото, потом он
  резко закрывается потому что нету фото для показа!» + «в некоторых
  местах макеты фото выстреливали и сразу закрывались». The old gate was
  "URLs exist" — the section appeared, then every page failed to download
  and the section vanished a second later. v6.2: a candidate URL joins
  the carousel ONLY after PhotoCache downloaded AND decoded its bytes —
  the section is built from actually-alive photos, so it can neither pop
  in empty nor collapse; the Wikipedia block is decoupled from the photos
  and lands on its own; still no broken-image icons anywhere.
- **56 offline countries, alphabetically sorted, localized.** The user:
  «В оффлайн картах страны не все и расставь их по алфавиту а не россия
  наверху!». +29 countries (Ukraine, Moldova, Denmark, Norway, Ireland,
  Hungary, Romania, Bulgaria, Serbia, Croatia, Slovenia, Montenegro,
  Slovakia, Lithuania, Latvia, Estonia, Japan, South Korea, China,
  Vietnam, India, Indonesia, Israel, Morocco, Tunisia, Mexico, Brazil,
  Argentina, Chile, Canada, Australia…), every country carries a stable
  key, the display name is localized (ru/fr/en/es/de) and the catalog is
  sorted alphabetically in the user's language — Россия now sits between
  Румыния and Сербия. Search matches localized names too.
- **Spanish + German, English first.** The user: «добавь испанский язык
  и немецкий а первым по дефолту ставь английский!». Every one of the
  ~350 strings is fully translated to Español and Deutsch (no half-
  translated UI), the language picker is English → Español → Deutsch →
  Français → Русский, and fresh installs default to English.
- **The card still answers only about THE place** (v6.1 identity rule
  stands): when the tapped name and the reverse-geocoded object disagree,
  all personal fields are discarded — a restaurant never gets the
  commune's biography again. City taps keep their flag / coat of arms /
  population.
- **The card still loads fast** (v6.1 speed work stands): ONE Wikidata
  call, parallel branches, session cache for instant re-taps, progressive
  blocks, junk-filtered Commons geosearch.

Earlier releases brought: the v6.1 smooth native map with the keyed
wake-rebuild (lock-screen bug dead, zero scroll lag), tappable flat
buildings with floors/height, the premium Wikipedia block, strict photos
of the tapped place, the glowing shimmer, the clean navigation cockpit
(real bottom-sheet HUD, round km badge, top strip), speed limits with the
Google-Maps red plate, speed camera warnings, speedometer, arrival card,
long-press map menu, A→B→C stops, recents, colored pins, auto-night,
scale badge, haptics, share, push navigation on the locked screen,
public transport, 16 map themes, satellite hybrid, camera memory,
racing OSRM+Valhalla router, ru/fr/en/es/de.

## What's inside

- **Nineteen MAP themes** (`lib/map/style_pack.dart`, `enum MapStyle`,
  `lib/map/map_catalog.dart`, `lib/map/apple_docs.dart`)
  - **Classic** — OpenFreeMap **Liberty** (111 professional layers: road
    hierarchy, tunnels/bridges, real POI sprites, road shields, native
    `building-3d` extrusion). Free, no API key. Flat buildings uncapped.
  - **Graphite** — Carto **Positron**; **Noir** — Carto **Dark Matter**.
  - **Forest** — Liberty repainted into a premium sage palette.
  - **Satellite** — Esri World Imagery + Liberty vector labels (hybrid).
  - **Relief** — OpenTopoMap (contours + hillshading).
  - **Premium recolors** — Midnight, Amethyst, Emerald, Abyss, Espresso
    (dark) and Pearl, Sand, Arctic, Rose, Mint (light).
  - **Bright** — keyless OSM Bright (OpenFreeMap, v6.3 bake-off).
  - **Atlas & Onyx (v6.5)** — the two mega-premium Apple-Maps-like
    cartographies: complete inline documents + canvas-drawn POI chips
    (`poi_chips.dart`); style source MIT © dddevid, adapted for Navigo
    (fonts, building uncap, Bordeaux rule, chips). In the SPIRIT of
    Apple Maps — not affiliated with or endorsed by Apple.
- **Fade-in map lifecycle masking v6.5** (`lib/ui/home_screen.dart` —
  `_coverMap` / `_revealMap` / `_scrimColor`) — the anti-flicker fix
  that works for both renderers; the A/B renderer toggle stays in
  Settings untouched.
- **Voice v6.2** (`lib/route/voice.dart` + manifest) — TTS_SERVICE
  package-visibility fix, step-wise init with BCP-47 language probing,
  `enabled` gate synced from the sound toggles, static instance for the
  settings «Проверить голос» test row; maneuver sentences stay in sync
  with the HUD text via `maneuver_text.dart`.
- **Instant place flow v6.2** (`lib/ui/home_screen.dart`) — the tap
  handler opens the card on tile data and hands enrichment to the card;
  the guard covers only platform-channel picks; long-press reverse
  geocode capped at 4 s.
- **Progressive card v6.2** (`lib/ui/place_sheet.dart`) — live header
  (name + address grow in place), live building info (type glyph, floors,
  height from the full OSM tags), the photo carousel fed by a
  download-gated queue, the Wikipedia block as state with a late
  second pass for nameless pins/buildings.
- **Nominatim gate v6.2** (`lib/places/place_media.dart`) — serial
  1.05 s-spaced queue for every reverse call, session cache (48 entries),
  7 s timeouts, the identity rule (`WikiService.nameMatches`) that strips
  mismatched objects down to their positional address.
- **Photo pipeline v6.1** (`lib/places/photo_cache.dart`) — UA-compliant
  download, image-only content check, decode validation, memory + LRU
  disk cache (48 MB, pruned at boot); dead URLs are dropped, never
  rendered.
- **Wiki engine v6.1** (`lib/places/wiki.dart`) — ONE `wbgetentities`
  call (+ a chase call for linked flag/emblem items), parallel Commons
  geosearch (junk-filtered), strict name matching, candidate ranking,
  per-language sitelinks, SVG→PNG rasterization of flags/coats of arms.
- **Navigation HUD v5.9** (`lib/ui/route_panel.dart`) — `NavTopBar`
  (exit circle + round distance badge + arrival pill + sound/overview),
  `_NavSheetFrame` (draggable real sheet), `NavHud` (speed-limit sign +
  round speed dial + maneuver line + progress), `TransitHud` on the same
  frame.
- **Wake fix v6.1** (`lib/ui/home_screen.dart` `_reviveMapAfterWake`) —
  native SurfaceView stays; after a real pause the map view is rebuilt
  with a fresh key at the captured camera; `MapEngine.attach` is
  re-entrant; cameras/roadworks/favorites re-attach automatically.
- **Compass v6** — flutter_compass stream, 1.2° repaint gate; navigation
  keeps the GPS course.
- **Round scale badge v6** — 48 px glass circle with the live scale.
- **Navigator marker** (`lib/map/sprites.dart`) — canvas-drawn arrow /
  car / bike / person sprites on a bearing-rotated symbol layer.
- **Transit routing v5.7** — keyless Transitous (MOTIS) plan + geocode,
  GTFS line colors, real-time flags, follow session by GPS + schedule.
- **Turn-by-turn notifications v5.7** — location foreground service,
  heads-up lock-screen notification with the next maneuver + ETA +
  camera distance.
- **Driving assist v5.8** (`lib/route/speed_limits.dart`,
  `speed_cameras.dart`, `overpass.dart`) — Overpass corridor maxspeed,
  device-side way matching, route cameras cached 14 days, two-stage
  alert FSM with TTS + haptics.
- **Offline maps v6.2** (`lib/ui/offline_sheet.dart`,
  `lib/offline/regions.dart`) — **56 countries / 90+ regions**, stable
  country keys, localized display names, alphabetical sort in the user's
  language, 3 detail levels, native offline packs with progress,
  installed list, delete.
- **Localization v6.2** (`lib/core/strings.dart`) — 5 complete languages
  (en, es, de, fr, ru; ~350 keys each), English default & first, the
  offline country names localized in all five.
- **Route service v5.5** — OSRM + Valhalla alternatives, avoid
  tolls/motorways/ferries, toll/highway/ferry badges.
- **Bulletproof loading** — ≤6 s pre-flight probe, watchdog, simplified
  raster fallback, auto-recovery.
- **Camera memory** — the app always opens where the user closed it.

## Build

Locally:

```bash
flutter pub get
flutter build apk --release --target-platform android-arm64 --split-per-abi
```

The APK lands in `build/app/outputs/flutter-apk/`. Toolchain that is known to
produce this app: Flutter 3.44.3, JDK 21 (the target `maplibre_gl` 0.27 needs)
and compileSdk 36, which is Flutter 3.44's default.

Signing is read from `android/app/key.properties` and the keystore it points
at. Both are git-ignored on purpose and must never be pushed. If the file is
missing, Gradle silently falls back to the debug key — fine for a test build,
useless for an upgrade path.

## Releases

Tags like `v6.9.0` are built on GitHub's own runners by
`.github/workflows/release.yml` and published to
[Releases](https://github.com/Vincentdiligent/Navigo/releases) with an arm64
and an armeabi-v7a APK attached. Pushing a tag is enough; the **Run workflow**
button builds without releasing. A tag is only published once the signing
secrets below exist — until then the run keeps the APKs as downloadable build
artifacts, because an APK signed with a runner's throwaway key is not
something to hand out.

For the CI APK to carry the real Navigo certificate, add these repository
secrets (Settings → Secrets and variables → Actions → New repository secret):

| Secret | Value |
| --- | --- |
| `KEYSTORE_BASE64` | the keystore file, base64-encoded |
| `KEYSTORE_FILE_NAME` | file name `storeFile` expects, e.g. `navilux.keystore` |
| `KEY_ALIAS` | key alias inside the keystore, e.g. `navilux` |
| `KEY_PASSWORD` | key password |
| `STORE_PASSWORD` | keystore password |

Encode the keystore without ever putting it in the repository:

```bash
base64 -w0 android/app/navilux.keystore > keystore.b64   # Git Bash
certutil -encode android\app\navilux.keystore keystore.b64  # PowerShell
```

Paste the contents of `keystore.b64` into `KEYSTORE_BASE64`, then delete the
`.b64` file. CI decodes it into `android/app/` for the duration of the build
only. Without those secrets the pipeline still produces an APK — signed with
the runner's throwaway debug key.

One honest caveat about installing: an APK signed with the release keystore
cannot replace a debug-signed Navigo that is already on the phone, because
Android refuses mixed signatures. That one-time switch needs an uninstall,
which clears saved places and downloaded offline maps — back them up or be
ready to re-add them.

## Data sources & licenses

- Map data © OpenStreetMap contributors; vector tiles & Liberty style by
  OpenFreeMap; Positron & Dark Matter styles by CARTO (GL vector).
- Atlas & Onyx styles: adapted from
  github.com/dddevid/MapLibre-GL-JS-AppleMaps-Style (MIT), cartography in
  the spirit of Apple Maps; Apple Maps is a trademark of Apple Inc. —
  this project is independent and not affiliated with Apple.
- Satellite imagery: Esri World Imagery (Esri, Maxar, Earthstar Geographics).
- Relief: OpenTopoMap (CC-BY-SA). Simplified mode: OpenStreetMap raster tiles.
- Routing: OSRM (FOSSGIS e.V. + demo server) + Valhalla
  (valhalla1.openstreetmap.de). Roadworks/closures: Overpass API (OSM data).
- Speed limits & speed cameras: OpenStreetMap tags via the Overpass API
  (mirrors: overpass-api.de, kumi.systems, maps.mail.ru, private.coffee).
  Coverage follows OSM contributors — no guarantee of completeness.
- Place photos & wiki knowledge: Wikimedia Commons / Wikipedia REST /
  Wikidata (CC-licensed files and text, attribution flows with the file
  and article pages). Place details: Nominatim / OpenStreetMap.
  The Wikimedia User-Agent policy requires a contact-bearing UA — Navigo
  sends a compliant one (generic clients get 403). Nominatim's usage
  policy (max 1 req/s) is enforced by an in-app serial gate.
- Public transport: Transitous (api.transitous.org) aggregating official
  GTFS feeds (IDFM / RATP / SNCF and the whole world).
- Voice: the device's installed TTS engine (Google TTS or similar);
  language availability depends on the engine, English is the fallback.
- Auto-night: NOAA solar-position math (no API).
- Legality note: speed-limit and camera data come from community
  OpenStreetMap mapping and may be incomplete or outdated in some regions.
