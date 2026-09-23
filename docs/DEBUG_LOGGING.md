# Debug logging and battery overhead

The Apple diagnostic capture is compiled with `NOOP_SYNC_DIAGNOSTICS`. The iOS
capture writes local JSON lines to `Documents/DebugDiagnostics`, retains two files
of at most 1 MiB each, and stops 24 hours after its first launch. Relaunching does
not extend the deadline. No upload or additional diagnostic timer is created.
Removing the compilation flag disables the capture. The current project enables it.

Source comments marked **`DIAGNOSTIC BATTERY COST`** identify instrumentation that
can increase energy use. The capture-start journal entry lists those areas too.

| Area | Evidence collected | Possible battery overhead and bounds |
| --- | --- | --- |
| UI body counters | Root tabs, liquid Today, Live, and the live log card; active versus nonactive evaluations | A deadline/state check and in-memory counter update per evaluation. No observable state or file writes per render. These are body evaluations, not display frames or proof of visibility. |
| Animation counters | Sky, liquid vessel, tube and HR-thread timeline evaluations | A counter/state check per existing animation tick. No new animation ticks or writes. This is the highest-frequency new instrumentation and can add battery overhead. Timeline evaluations are not proof of visible display frames. |
| Log counters | Console versus other strap-log appends | A small check/counter update per append. Counts pressure on the published log without recursively appending diagnostic lines there. |
| History stage timing | Decode/scheduling, preparation, store insert, publication/reject archive, raw preparation, cursor write; repeated cursor and local ACK outcome | Several monotonic clock reads per chunk. At most one normal journal line per 30 seconds and one slow/failed line per 5 seconds; suppressed events are counted in the next line. Replaces the previous per-chunk published ACK timing line. |
| Analysis phases | Begin, scan return, full return, assertion expiry | Clock reads and a few journal writes per pass. Measures existing work; does not change cancellation or analysis scheduling. |
| Performance snapshots | Process CPU delta, elapsed time, accumulated UI/log counters | One process CPU read and journal append at existing lifecycle, sync, keep-alive, analysis-return and assertion-expiry events. Process CPU includes other simultaneous app work. |
| Existing BLE signal capture | RSSI and connection lifecycle, including failed connects | RSSI reads add radio traffic during the capture: healthy background links keep the existing five-minute policy; other qualifying states can use one minute. No new polling cadence or connection command is introduced. |
| Journal storage | Existing HealthKit, BLE and new performance events | JSON encoding and file operations consume CPU and storage energy. The 24-hour deadline and file rotation bound retention; writes bypass SwiftUI's published strap log. |

Elapsed stage times include scheduling and suspension; they are not CPU timings.
An ACK-prepared line proves local preparation only, not radio delivery. A repeated
cursor is not proof of an identical payload or duplicate stored rows. A return after
assertion expiry does not prove that work ran continuously while the app was suspended.
Battery measurements from a capture build include instrumentation overhead; compare
with a build without the flag before attributing that overhead to ordinary use.

The additional instrumentation is iOS-only. Shared pure timing/rate-limit helpers
are covered by `OvernightDiagnosticsTests`; analytics and stored data are unchanged.
