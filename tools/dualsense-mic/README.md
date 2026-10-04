# DualSense Bluetooth microphone experiment

The root `probe.c` is a bounded macOS research probe, **not a system microphone or a VibeWand release feature**. A later standalone experimental system microphone is available under [bridge](bridge/README.md). See [the investigation](../../docs/dualsense-microphone.md) for measured results and remaining work.

Requires macOS, Xcode command-line tools and libopus development files. It uses the machine's existing libopus; the build does not install anything.

From the repository root:

```sh
sh tools/dualsense-mic/build.sh
output/dualsense-mic/probe
output/dualsense-mic/probe --enable --exclusive
```

The first run reads reports for four seconds without enabling the mic. The second temporarily claims the Bluetooth DualSense exclusively, checks that reports are arriving, enables the microphone for about six seconds, sends three disable reports, and releases the device. Controller navigation is unavailable during the exclusive test. SIGINT/SIGTERM also run the disable sequence. SIGKILL, process crashes, connection loss, or blocked OS calls cannot guarantee cleanup; power-cycle the controller if reports stop or it remains in audio mode.

Only one Bluetooth `054c:0ce6` device may be connected. Edge and other variants have not been tested. The probe never changes the default audio input, installs a driver, records PCM to disk, plays audio or uploads speech. It outputs counts, CRC/decode errors, amplitude statistics and sequence gaps. Nonzero decoded samples establish packet reception; they do not establish intelligible, continuous speech.

An experimental `--interval-ms 10..500` controls the interval **after** each synchronous write completes. The default is 500 ms. Actual cadence includes OS write latency; shortening it did not resolve the local receive-rate limitation. The writer is separate from the receive run loop. No L2CAP attach/reconnect experiment is included: that disturbed the local connection and required a physical power-cycle.

Exit codes:

| Code | Meaning |
|---|---|
| 0 | Baseline received reports, or enabled run met the probe's limited checks; not product acceptance |
| 2 | Invalid arguments |
| 3 | Opus initialization failed |
| 4 | No unique matching Bluetooth device |
| 5 | HID open failed |
| 6 | Worker creation failed |
| 7 | No reports, or no decoded microphone frames |
| 8 | Invalid reports, decode errors, ambiguous sequence jumps, or over 5% missing microphone sequence positions |
| 9 | An enable/disable write failed; check device recovery |

`test-protocol.c` checks golden CRC values, tag precedence, invalid/truncated reports and a synthetic Opus encode/decode round trip. It does not touch hardware. The build runs these tests before compiling the probe.

`windows-inventory.ps1` is a read-only aid for locating the actual Windows device service and INF before investigating binaries. It has not yet been run on Windows. Run it separately with USB and Bluetooth connections, label the results, and review device identifiers before sharing. This script does not capture microphone packets; the later Windows transport comparison still requires instrumented HID capture or the reference application's telemetry.

Protocol references: [DS5Dongle](https://github.com/awalol/DS5Dongle), [DS4Windows](https://github.com/hbashton/DS4Windows), [dualsense-bridge](https://github.com/tomarai85/dualsense-bridge). The implementation here is a small native probe, not a copied Windows driver or redistributed community application.

Additional development flags: `--full-init` adds the audio state and silent-haptics section; `--quiet-sensors` also temporarily powers down touch/motion during the probe; `--report-us 1000..16000` requests and restores the HID interval property (acceptance does not prove a transport-rate change); `--seconds 1..120` changes the active capture interval. None enables Game Mode automatically. These flags are experiments, not established fixes.
