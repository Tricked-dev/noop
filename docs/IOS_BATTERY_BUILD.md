# iOS power-policy build guide

## Changes

- Standard HR receipt and routine flush-success diagnostics require Connection Test Centre mode. Always-on minute summaries, errors, and recovery messages remain. Durable log-tail mirroring is limited to once a minute during bursts, or five minutes during sparse activity, and flushed on lifecycle transitions.
- Health export compares the desired samples against this app's actual HealthKit records. It deletes/saves only changed samples, repairs duplicates, and naturally retries partial saves after a restart. Minute HR buckets reconcile the supported 14-day window instead of repeatedly rewriting a 48-hour overlap. Vitals, sleep groups, and workouts retain historical edits/deletions within that window. Failed source reads do not become empty replacement snapshots. Latest upstream open-night holdbacks remain excluded from both export and deletion reconciliation. These changes reduce writes, not all reads. Quantity comparison tolerates unit-conversion noise below 1e-9 in the export unit.
- HR Live Activity content is deduplicated, with two-second foreground and 15-second background change cadences. Unchanged content renews after 60 seconds, before its 120-second stale deadline. Activity creation is foreground-only, avoiding repeated rejected requests from a background HR stream. The widget extension remains embedded.
- Closed-day analytics intermediates persist in a disposable, protected Caches file. Cold reuse requires matching build, profile/configuration, locale, per-day keys, and a SHA-256 witness of the raw inputs. In-place edits, late streams, corruption, expiration, and configuration changes reject reuse. The downstream baseline/recovery pass still runs. Raw-content validation adds reads; profiling is needed to establish the net saving for a given history size.
- Battery polling is separated from the unchanged 30-second keep-alive/watchdog timer: normally 60 seconds foreground, 300 seconds background, 30 seconds charging. A WHOOP 4 link silent for 60 seconds retains the original probe cadence to avoid manufacturing watchdog reconnects. Charging and low-battery detection can be delayed up to the relaxed polling interval.

No analytics formula, sensor acquisition cadence, database schema, or portable backup field changes. Android remains unchanged: the changes concern Apple diagnostics, HealthKit, ActivityKit, and a disposable Apple cache; Codable/Equatable conformances do not change computed values. The source build remains watch-capable. `project-sideload.yml` excludes the Watch dependency for this IPA, matching the repository's usual sideload packaging, for iOS-only packaging.

## Build and verification

Generate with `xcodegen generate --spec project-sideload.yml`.

```sh
xcodebuild -project Strand.xcodeproj -scheme NOOPiOS -configuration Release \
  -destination 'generic/platform=iOS' -derivedDataPath build/ios \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= build
```

Regression coverage includes export duplicate repair/partial-save retry, Activity cadence/freshness, battery cadence and quiet WHOOP 4 behavior, diagnostic gating with retained errors/recovery, input-digest invalidation, and binary round-trip equality of a computed day's results.

Package the app with `Tools/prepare-ios-sideload-app.sh` and zip it under `Payload/`. This embeds replaceable ad-hoc capability signatures; it is not an Apple distribution signature. Sign with AltStore, SideStore, or Sideloadly before installing. Bundle identifiers and App Groups come from the build configuration. Re-sign using the same identity as an existing installation to preserve its app container; no existing installation is removed by this build process.

## Hardware acceptance still required

Hardware validation is required. Verify on WHOOP 4 and 5/MG independently: screen-off collection, reconnects, quiet/off-wrist liveness, charging detection, overnight HRV, Live Activity freshness, and Health edits/retries. Compare equal-duration release runs with identical settings/history; record CPU time, wakeups, storage activity, Health mutations, and phone/strap discharge separately. No percentage battery improvement is claimed.
