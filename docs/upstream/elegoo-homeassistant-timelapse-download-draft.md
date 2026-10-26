## Draft contribution for danielcherubini/elegoo-homeassistant (CC2 timelapse LAN download)

Target: new issue or PR against `danielcherubini/elegoo-homeassistant`
documenting the LAN download path for CC2 time-lapse videos.
English, no Access-Code / SN / IP in the text, no model-specific
secrets.

The addon's current `cc2/const.py` and `cc2/client.py` document
`method 1042` (live MJPEG stream on port 8080) but do **not** expose
the recorded time-lapse MP4 to the user. The code I looked at
(public repo on `main`) ends the time-lapse story at the camera
stream. The MP4 is reachable, with the usual LAN credentials, over
HTTP. Here is a measured reproduction on a real CC2 running stock
firmware OTA `02.01.01.07`.

---

### Measurements (one printer, printer idle, access code pairing)

- Firmware: `method 1001` reports `ota_version = 02.01.01.07`;
  `mcu_version` and `soc_version` reported empty.
- Pairing: `token_status = 1`, `lan_status = 1` (LAN-only mode on
  the display).
- Transport: MQTT 1883 for request/response; HTTP 80 for the
  download.

### `method 1036` (GET_HISTORY) returns the time-lapse index

Request on `elegoo/<sn>/<client_id>/api_request`:

```json
{"id":<rid>,"method":1036}
```

Response on `elegoo/<sn>/<client_id>/api_response`
(`result.error_code == 0`, full list — no pagination seen in 45
entries, matching the comment in `cc2-control/src/mqtt.c:353`
„1036 returns the whole print task list").

Each `history_task_list[]` entry includes:

| Field | Example | Notes |
|---|---|---|
| `task_id` | UUID string | stable per print start |
| `task_name` | `foo.gcode` | the G-code file name as uploaded |
| `begin_time`, `end_time` | Unix seconds | **printer-local clock**, see caveat below |
| `task_status` | `1` or `2` seen | terminal values 1..3 per `cc2-control/src/history.h:107`; running tasks don't appear in this list |
| `time_lapse_video_status` | `0`/`1`/`2`/`3` | see enum below |
| `time_lapse_video_url` | `""` / `picture/<name>` / `video/<name>.mp4` | path on the printer |
| `time_lapse_video_size` | integer bytes | 0 unless `status==2` |
| `time_lapse_video_duration` | seconds | 0 unless `status==2` |

Observed status distribution across 45 entries on one printer
(sample of real usage; probably not representative in general):

| `time_lapse_video_status` | Count | URL form | Meaning |
|---|---|---|---|
| 0 | 38 | `""` | no frames captured |
| 1 |  2 | `picture/<name><ts>` | raw frames present, not yet rendered |
| 2 |  5 | `video/<name><ts>.mp4` | MP4 rendered, downloadable |
| 3 |  0 | – | not seen in this sample |

`cc2-control/src/history.h:167` and
`cc2-control/web-src/preview/plugin.ts:792` treat 1 and 3 as
„renderable" (so 3 is probably „previous render failed, raw frames
retained"). 2 is „ready to download".

### `GET /download?X-Token=…&file_name=<url>` serves the MP4

Same endpoint as for G-code downloads, just with the
`time_lapse_video_url` from `method 1036`. Example of a successful
read-only request:

```
GET /download?X-Token=<access>&file_name=video%2F<name>%3Cts%3E.mp4 HTTP/1.1
Host: <printer-ip>
```

Response headers:

```
HTTP/1.1 200 OK
Content-Length: 1741634
Content-Disposition: attachment; filename="video/<name><ts>.mp4"
Transfer-Encoding: chunked
```

The response has both `Content-Length` and
`Transfer-Encoding: chunked` set, which is an RFC-9112 collision.
cc2-control's relay in `src/history.h:269-273` prefers chunked when
the body actually is chunk-framed; worth doing the same here to be
safe. The body itself was a valid H.264 MP4 (`ffprobe` reports
H.264 / 640×360 / 30 fps / 100 frames / 3.3 s on a 100-layer test
print — one frame per layer; your mileage will vary with
`total_frames` the camera module was told at `TimeLapseStart`,
which Elegoo's `ai_camera` module publishes in its own code at
`elegoo/extras/ai_camera/module/util/time_lapse_control.cpp:28`).

### `method 1051` (TIMELAPSE_RENDERING) for `time_lapse_video_status == 1`

cc2-control's flow in `cc2-control/src/mqtt.c:362-372`:

```
{"id":<rid>,"method":1051,"params":{"url":"<time_lapse_video_url>"}}
```

Reply is immediate; progress is reported by `machine_status.status`
transitioning to **12** (`cc2-control/src/mqtt.c:362` has the
comment „1051 acknowledges a render request; machine state 12
reports its progress"), with `sub_status` 3020 then (usually)
3021 before going back to idle. On a 100-layer / ~15-minute print,
the matching USB-triggered composite took **26 s** on my printer
(sub_status went `3020→3021→1`). After it finishes, `method 1036`
shows the task flipped to `video_status=2` with a `video/<name>.mp4`
URL.

### Important: `method 1036` is a database, not a filesystem listing

The history is **not** kept in sync with on-device operations
performed via the printer's display. On my printer today I had
deleted all older time-lapses at the display (Settings → Camera)
before testing. `method 1036` continued to return every one of
those entries with their original `time_lapse_video_status=2`
and video URLs. A `GET /download` against those URLs timed out
after the full read-timeout — the printer stays silent on
non-existing `file_name`s (see
`cc2-control/src/history.h:250-251`), it does not return 404 or
any other HTTP error. The one entry still present on the printer
answered `HTTP 200` with the full MP4 immediately.

Table of the four `video_status=2` entries I tried (one line per
entry; last column is wall-clock behavior of the HTTP GET from
a LAN host):

| Deleted at display? | video_size (bytes) | HTTP head latency |
|---|---:|---|
| yes | 9 912 573 | 8 s timeout |
| yes | 1 813 428 | 8 s timeout |
| yes | 1 762 496 | 8 s timeout |
| no  | 1 741 634 | 74 ms, `HTTP 200`, body matches |

**Suggestion for the integration:** do not render a download link
or „video ready" sensor state based on `video_status==2` alone.
Probe the URL with a short Content-Length-only `HEAD`-style GET
(or a GET with ~1-2 s read-timeout on the response headers); treat
non-answer as „not available" and only show the download when the
printer actually serves a response head. This is also the natural
way to recover from the display-side delete, which the firmware
otherwise does not reflect anywhere observable over MQTT.

### Second observation: parallel downloads are safe

Separately, when a `GET /download` for a deleted URL hangs
(printer stays silent until the client read-timeout), a parallel
`GET /download` for a still-existing URL still answers in ~20 ms
on the response head. The printer accepts multiple TCP
connections and services them independently. In practice,
probing many entries in parallel is fine as long as the client
caps concurrent downloads at two (matching cc2-control's own
„two-transfer limit" in `src/history.h`). Treat `connect`
latency as unreliable (14 – 420 ms observed, varying between
runs); use `response-head` latency as the only reliable
success/fail signal for the probe.

### Fourth observation: Status 2 means „raw frames already consumed"

A follow-up test sent `method 1051 params.url=picture/<basename>`
against the same `video_status=2` entry (the URL exactly as a
hypothetical Status-1 version of this task would have carried it).
Same outcome as the `video/…` form: `error_code=0` in 18 ms,
`status 12 ↔ sub_status 3020 → 3022 → 1` in under a millisecond,
no change to the MP4, no change to the history. **The target MP4
was NOT re-rendered** — the download after the call returned the
same bytes with the same md5 as the pre-call baseline.

Looking at the ai_camera composite path makes this consistent:
`elegoo/extras/ai_camera/module/util/time_lapse_control.cpp:119-125`
removes the raw-frame directory with `rm -rf` at the end of
`Composite()`, so once a time-lapse has transitioned to
`video_status=2` the raw frames under `/opt/usr/picture/<basename>/`
are gone. A subsequent 1051 on the same task cannot find anything
to render; it just flashes `sub_status 3022` and returns to idle.

Across three different tests on different tasks we always saw
the same `3022` signal when no raw frames were available:

| Scenario | URL form | Raw frames | Status 12 duration |
|---|---|---|---:|
| old entry, frames purged at display | `picture/<basename>` | gone | ~1 s |
| today's entry, Status 2, wrong URL | `video/<basename>.mp4` | gone (post-composite) | 1 ms |
| today's entry, Status 2, correct URL | `picture/<basename>` | gone (post-composite) | <1 ms |

**Practical implications for the integration:**

- `1051` cannot re-render a `video_status=2` entry on this
  firmware. Expose the „Render" action only on `video_status=1`
  (and `3`, which the firmware's code treats as renderable but
  likely never has retained raw frames either). Status 2 entries
  only ever get the download action.
- `sub_status 3022` consistently means „no raw frames at the
  requested path", regardless of why they are missing (never
  captured, deleted at display, or consumed by a previous
  composite). Treat it as a non-fatal „nothing to do" signal
  rather than a hard error.
- Even with the correct `picture/<basename>` URL form against
  a Status-2 target, the firmware does not overwrite or touch
  the existing MP4. 1051 is observably idempotent across all
  tested URL forms when raw frames are absent.

A fully confirmed success path (`3020 → 3021 → 1`) over MQTT
remains outstanding; it needs a fresh print whose raw frames
haven't yet been consumed by any composite (neither USB export
nor an earlier 1051).

### Third observation: 1051 is idempotent on `video_status=2`

I ran a controlled test by sending `method 1051 params.url=
"video/<name>.mp4"` against a known-good `video_status=2` entry
where the MP4 was already available. Behavior:

- Reply arrived in 500 ms with `result.error_code=0` and a
  curious `result.url = "video/<name>.mp4.mp4"` — the firmware
  appended `.mp4` to the already-`.mp4`-terminated path. This
  tells us the firmware treats `params.url` as a basename and
  looks for raw frames under `/opt/usr/picture/<params.url>/`
  — which does not exist for a `video/…`-form URL, so the
  composite immediately fails.
- `machine_status.status` transitioned 1→12→1 in **1 ms**, with
  `sub_status 3020 → 3022`.
- `method 1036` afterwards: **byte-identical** to the pre-1051
  snapshot. No fields mutated, not even the
  `time_lapse_video_duration` field (which did mutate 0→4 on a
  separate 1051 call against a `video_status=1` entry whose raw
  frames had been removed — perhaps that mutation is tied to the
  `picture/`-form URL).
- The MP4 file itself, downloaded again after the 1051, was
  **byte-identical** to the pre-1051 download (same length, same
  md5).

**Practical implications for the integration:**

- `1051` with the `video/<name>.mp4` form has no visible effect
  on the data: no overwrite, no history change, no new file.
  Safe to call accidentally.
- To actually trigger a render, pass the `picture/<name><ts>`
  URL (the one `method 1036` returns while
  `time_lapse_video_status` is 1 or 3). The `video/…`-form URL
  is only useful for the download endpoint, not for 1051.
- Treat `sub_status 3022` as „composite did not happen" (two
  known reasons: raw frames absent, or URL form wrong). The
  only reliable success signal is a head-probe on the expected
  `video/<name>.mp4` URL after the status returns to 1.

### Realtest observations on `method 1051`: confirmed success path

Follow-up to the inconclusive runs: ran the full
`method 1051 params.url=picture/<name><ts>` cycle from an app
against a freshly captured time-lapse (raw frames still on the
printer, no USB export in between). Result: **the method
produces a usable MP4 over MQTT**, and the full flow — `method
1036` → „render" button → `method 1051` → wait for
`machine_status.status == 12` to leave → re-poll `method 1036`
→ GET `/download?file_name=video/<name>.mp4` — works end to end.

Observations worth having in the integration:

- `method 1051` replies immediately with `result.error_code = 0`;
  the reply's `result.url` already points at the eventual
  `video/<name>.mp4`, but the file does not exist yet.
- `machine_status.status` transitions to 12 for the duration of
  the composite, then back to 1 when it is done. On a 100-frame
  (~3-second) clip on a Centauri Carbon 2 with firmware
  02.01.01.07, the USB-triggered variant of the same composite
  took ~26 s; the MQTT variant on the same printer is in the
  same order of magnitude (not benchmarked to the millisecond in
  my test).
- After `status` returns to 1, `method 1036` shows the target
  task with `time_lapse_video_status = 2` and the URL rewritten
  to `video/<name>.mp4`. A short HTTP GET against that URL
  succeeds, Content-Length matches `time_lapse_video_size` from
  the history entry, and the body is a valid MP4 (H.264 /
  640×360 / 30 fps in my tests).
- The printer's **display shows no dialog** during an MQTT-
  triggered 1051. The USB-export path shows „Generating
  video" / „Copying video" while the sub_status walks
  `3020 → 3021`, but a 1051 from LAN runs silent on the
  display. The only user-visible progress signal is the
  `api_status` stream — the integration should drive its spinner
  from `machine_status.status == 12`, not expect any
  display-side event.

### Earlier `3022` runs (why they are not success)

Two separate 1051 runs on different `video_status=1` entries
produced `machine_status.status 1 → 12 → 1` in **under a
second**, with `sub_status 3020 → 3022` and no change to
`time_lapse_video_status`. Both runs were against entries whose
raw frames were no longer on the printer (one was 12 days old
and had been deleted at the display; the other was for a
`video_status=2` entry — the composite had already consumed
its own raw frames). So:

- `sub_status 3022` means „no raw frames at the requested
  path", independent of why they are missing (never captured,
  deleted at display, consumed by a previous composite, or
  wrong URL form).
- The ai_camera composite path checks the directory first
  (`elegoo/extras/ai_camera/module/util/time_lapse_control.cpp:93-107`)
  and bails out when absent; the failure is only reflected in
  the sub_status transition, not in the MQTT `error_code`.
- The window where 1051 can succeed on this firmware is narrow:
  **a `video_status=1` entry whose composite has not yet been
  triggered by any path** (display USB export, or an earlier
  1051). After the first successful composite the raw-frame
  directory is `rm -rf`'d by the ai_camera module.

**Suggestion for the integration:** treat 1051 success the same
as every other time-lapse state check — probe the resulting URL
with a short HTTP GET. Do not infer success from
`error_code = 0` or from `status == 1` after `status == 12`.
When a `video_status=1` entry is older or has already been
inspected via display, the next render attempt is likely to end
in `3022` with no MP4; this is a non-fatal „nothing to do"
signal.

### Printer clock caveat (expanded)

The printer's clock is not synced to real time. On my printer, a
print that started at 07:38:07 Europe/Berlin on 2026-10-26
produced a time-lapse filename stamp of `20261026143807` — i.e.
the printer thought the local time was 14:38:07 (UTC+8), which
matches China Standard Time regardless of my printer's physical
location in Germany. The Elegoo code reads the clock with
`localtime_r`
(`elegoo/extras/ai_camera/module/util/time_lapse_control.cpp:166-172`),
so whatever TZ the system has configured ends up in the filename.
Treat `begin_time`, `end_time` and the filename stamp as opaque
ordering keys only; do not compare them against the HA host's
clock.

### Fifth observation: `method 1038` is history-only, nothing else

The companion „delete" method for a history entry is `1038`. I
sent one explicit `method 1038 params={"list":["<task_id>"]}`
against a `video_status=2` entry on my printer (payload shape
per `cc2-control/src/mqtt.c:343-346` + `src/history.h:123-142`).
Behavior:

- Reply arrived in ~300 ms with `result.error_code=0`. No
  `machine_status` transition observed; the delete is pure
  database work.
- `method 1036` after the call: the target `task_id` is gone,
  `result.total` dropped from 45 to 44, every other entry is
  byte-identical. (Side note: `result.total` appears to be a
  consistency counter the firmware emits alongside the task
  list; the cc2-control code I checked doesn't read it, but
  the integration might.)
- `GET /download?X-Token=…&file_name=<the removed entry's URL>`
  **still returned the MP4 with HTTP 200 and the same md5**.
  The file at `/opt/usr/video/<basename>.mp4` is unaffected.
- The owner reported the display still lists the time-lapse
  entry after the MQTT delete.

This gives a clean division of responsibilities on the stock
firmware:

| Delete path | 1036 history | MP4 on disk | Display list |
|---|:-:|:-:|:-:|
| `method 1038` (MQTT) | removed | kept | kept |
| Display delete (manual) | kept (stale) | removed | removed |

**Practical implications for the integration:**

- Treat `method 1038` as UI housekeeping, not as a way to free
  printer storage. The MP4 stays on the device; only the owner's
  on-screen interaction frees that space.
- When exposing a „delete" action in the UI, be explicit about
  which side it affects. Removing the entry from the integration's
  history view via `1038` is cheap and does not touch the owner's
  time-lapse library on the printer itself.
- After `1038`, refresh `method 1036` and rebuild the task list;
  don't optimistically splice out the entry — the firmware also
  updates `result.total` and the integration can use it as a
  consistency check.

### Caveats worth documenting at the integration level

1. **The printer clock drifts, so `begin_time` / `end_time` are
   not usable as wall-clock timestamps.** On my printer I observed
   a shift that put the filename stamp of a 2026-10-25 18:05 MEZ
   print at `20261026010053`. Treat it as an opaque ordering key.
2. The `.mp4` filename in `Content-Disposition` is the raw
   `video/<name><ts>.mp4` (relative path), which some clients
   interpret as a folder-including name. Expect to clean it on
   the client side.
3. `method 1047` (DELETE_FILE) does **not** delete time-lapse
   entries on this firmware (returns `error_code=1003` regardless;
   see the companion issue #432 draft). The documented delete path
   is `method 1038 params={"list":[task_id, …]}`
   (`cc2-control/src/mqtt.c:343-346`). Deleting a history entry
   also drops the associated time-lapse frames / MP4.
4. `method 1044` (GET_FILE_LIST) does not expose the `video/`
   folder; the only index is `method 1036`.

### Where this would help

The current cc2 integration has an entity for the live camera
stream but no path to the recorded time-lapse. A sensor /
diagnostic exposing `history_task_list` (with the three video
columns above) plus an optional `camera.record` service calling
`method 1051` and then offering the MP4 via a URL would make this
useful end-to-end.

Happy to split this into:

- a documentation PR extending `docs/CC2_PROTOCOL.md` with the
  `method 1036 / 1051 / 1038` definitions and the `/download`
  path semantics; and
- a feature PR adding a time-lapse download helper to
  `cc2/client.py`.

No code copied from `cc2-control` or `elegoo-link`; the above is a
protocol-level write-up based on observed exchanges plus the public
Apache-2.0 adapter header `elegoo_fdm_cc2_message_adapter.cpp` for
the method-number meanings.
