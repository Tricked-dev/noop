# iOS development changes

This branch contains iOS sync and live-stream fixes, bounded local diagnostics, and selected upstream
Apple changes. Android is outside the branch's implementation scope; cross-platform parity is not
claimed. Generated artifacts, device captures, deployment records, and signing overrides stay local.

## Sync and diagnostics

History and live traffic use separate frame reassembly state. Response handlers require the expected
packet type and integrity verdict. Restored subscriptions are coalesced; history starts after the
required notifications are active. Stream-mode changes are deferred during history transfer and
applied in HR-before-raw order afterward. A completed transfer uses its own saved history frontier
to decide whether immediate continuation is needed.

The iOS WHOOP 4 watchdog starts a new observation window after delayed keep-alive callbacks.
Silence while the process was suspended does not by itself justify reconnecting. Existing polling
and notifications supply liveness evidence; no additional recovery timer is introduced.

`NOOP_SYNC_DIAGNOSTICS` enables a temporary local event journal with a persisted expiration and two
bounded files. Events cover lifecycle and connection changes, transfer summaries, first-live-sample
latency, Health pass outcomes, and analytics costs. The recorder adds no wake timer or network
transfer. Extra signal-strength reads stop when the capture expires. Compile out the flag for a
normal build. Device journals and their contents are not public test fixtures.

## Upstream attribution

| Source | Adaptation |
| --- | --- |
| [Live export diagnostics](https://github.com/ryanbr/noop/pull/2367), @ayiskakov | Include dynamic database diagnostics in saved Live logs. |
| [Metrics caption](https://github.com/ryanbr/noop/pull/2377), @andremiliano | Hide the history-window caption when detailed charts are disabled. |
| [Imported skin temperature](https://github.com/ryanbr/noop/pull/2285), @Iskrata | Store and export absolute temperature; repair affected imports while preserving unrelated fields. |
| [Health write deferral](https://github.com/ryanbr/noop/pull/2298), @Iskrata | Adapt the protected-data unlock gate while retaining existing HR reconciliation. Broader fingerprint caching is not included. |

The upstream refresh also includes open-night Health write-back deferral, the Today weight tile's
Health/profile source, alarm readout corrections, display/import fixes, and background scoring
retry/pacing changes. Original upstream attribution is retained. Cross-platform repository-baseline
checks can report divergence because this branch does not update the independent Android code.

## Building and checking

`project.yml` is the generated project's source of truth. Personal identifiers belong only in the
ignored `Config/BundleIdSecrets.xcconfig`; see the example configuration for optional overrides.
Do not publish signed packages or provisioning material as part of a source change.

Generate the project with `xcodegen generate`. Build the `NOOPiOS` scheme for an iOS device destination.
Mac app tests must use `NOOP_TEST_HOST`, which avoids starting production services and Bluetooth;
that flag must not be present in an iPhone build. Pure protocol tests use synthetic inputs for new
regressions. Compilation and unit tests do not establish battery savings or long-term BLE reliability.
