# iOS background power policy

- Screen-owned realtime requests are masked while iOS is backgrounded and restored on foreground entry. Manual workouts, live coaching and lifting own separate requests, so dismissing a view or locking the phone does not stop an active recording. Continuous HRV capture retains its existing opt-in and overnight window. The existing reversible stream commands are used; notification subscriptions, liveness deadlines and the connection handshake are unchanged.
- When signal diagnostics are enabled, RSSI reads stretch from 60 to 300 seconds on healthy background links. Unknown or weaker-than-−80 dBm RSSI, 60 seconds without incoming data, and Connection Test Centre diagnostics retain the faster cadence. The first read remains immediate. Less frequent range evidence is the deliberate tradeoff.
- Apple Health export keeps a durable pending token before work starts. Failed, interrupted or open-night-held exports retain an hourly earliest retry; successful reconciliation schedules a daily repair pass for external deletions and missed signals. A newer data signal cannot be cleared by an older export finishing. Reopening the app does not move the pending deadline. BackgroundTasks still controls actual execution times.
- iPhone Low Power Mode stretches automatic background offloads to at least an hour, including strap-prompted requests. Manual, foreground, connection and ongoing-backlog triggers retain their existing behavior. New background scoring is deferred; its processing request requires external power while Low Power Mode is enabled and is replaced when that mode changes. Foreground scoring and already-running work continue. These policies do not disable overnight HRV or active recording.

These additions are Apple lifecycle and scheduling changes. Android, score formulas, the shared schema and backup settings are unchanged. Hardware acceptance must include locking with only Live open, locking during each recording mode, unlocking, reconnecting while locked, Low Power Mode transitions, and held/failed Health export retries.

## Verification

Run the StrandAnalytics suite and the app regression suites for realtime demand, lifting lifecycle,
Health export retry state, Low Power Mode scoring/offload gates, standard-HR persistence and reconnect
policy. Build the iOS NOOPiOS Release target and the macOS Strand test host with `NOOP_TEST_HOST`.
Run source-hygiene lint and whitespace checks.

Compilation and policy tests do not establish battery savings or hardware behavior. Acceptance also
requires an iPhone/strap energy measurement, screen-off Bluetooth checks and live HealthKit integration.
