# Draft contribution for danielcherubini/elegoo-homeassistant

Notes on the LAN time-lapse surface on CC2 stock firmware, measured
on one printer and reproduced across several sessions. English, no
SN / IP / access code in the text, no code copied from
`cc2-control` or `elegoo-link`. The integration today documents
`method 1042` (live MJPEG) but does not expose the recorded
time-lapse MP4; everything below is read-only probing plus one
confirmed render path.

## 1. Setup

- Firmware: `method 1001 software_version.ota_version = 02.01.01.07`,
  `machine_model = Centauri Carbon 2`. `mcu_version` and
  `soc_version` were reported empty on this printer.
- Pairing: `token_status = 1`, `lan_status = 1`.
- Transport: MQTT 1883 (user `elegoo`, password = access code) and
  HTTP 80 (`X-Token` = same access code).

## 2. `method 1036` is a database, not a filesystem

`result.history_task_list[]` — one call, no pagination. Also
`result.total` as a redundant count.

| Field | Example | Notes |
|---|---|---|
| `task_id` | UUID | stable per print start |
| `task_name` | `foo.gcode` | the G-code file name |
| `begin_time`, `end_time` | Unix seconds | printer-local clock; see §6 |
| `task_status` | `1`, `2` seen | terminal values 1..3 |
| `time_lapse_video_status` | `0..3` | see enum below |
| `time_lapse_video_url` | `""` / `picture/<name>` / `video/<name>.mp4` | path on the printer |
| `time_lapse_video_size` | integer bytes | > 0 only when `status==2` |
| `time_lapse_video_duration` | seconds | > 0 only when `status==2` |

Enum (empirical, 45 entries plus follow-up tests):

| `time_lapse_video_status` | URL form | Meaning |
|---|---|---|
| 0 | `""` | no frames captured |
| 1 | `picture/<name><ts>` | raw frames present, no MP4 yet |
| 2 | `video/<name><ts>.mp4` | MP4 rendered, downloadable |
| 3 | `""` | render has been attempted; raw frames absent |

**Database vs. filesystem.** This list is kept separately from the
printer's on-device state. Deleting a time-lapse via the printer's
display does **not** update `method 1036`: in one session all older
entries were deleted at the display, and 1036 kept returning them
with `time_lapse_video_status = 2` and their original URLs. The
only way to tell whether a listed MP4 is still really there is to
try the download; see §3.

## 3. `GET /download` for the MP4

Same endpoint as the G-code download, just with the
`time_lapse_video_url` from 1036 as the query:

```
GET /download?X-Token=<access>&file_name=video%2F<name><ts>.mp4 HTTP/1.1
Host: <printer-ip>
```

Response on an existing file:

```
HTTP/1.1 200 OK
Content-Length: <bytes>
Content-Disposition: attachment; filename="video/<name>.mp4"
Transfer-Encoding: chunked
```

Two things worth encoding in the integration:

- **Both `Content-Length` and `Transfer-Encoding: chunked` are
  set.** `cc2-control`'s own relay in `src/history.h:269-273`
  prefers chunked when the body is actually chunk-framed; worth
  doing the same.
- **Non-existing `file_name` → silence, not 404.** The TCP
  handshake succeeds, the request line is sent, the printer then
  stops responding. Only the client's own read-timeout terminates
  the session. This is the "wrong token or name" signature called
  out in `cc2-control/src/history.h:250-251`.

**Head-probe recommendation.** Do not render a download link based
on `time_lapse_video_status == 2` alone (see §2). Probe the URL
with a short response-head read; treat anything but a `200` within
~1–2 s as "not available". A measured sample:

| URL state | response-head latency | HTTP |
|---|---:|:-:|
| MP4 present | ~70 ms | 200 |
| MP4 deleted at display | 8 s read-timeout | – |

**Parallelism.** A hanging GET on a missing URL does not block
other GETs: on the same printer a parallel probe for the one
surviving MP4 answered in ~20 ms while another request held the
connection open for 35 s before timing out. `cc2-control` caps
itself at two concurrent transfers; same bound here is a safe
default.

## 4. `method 1051` (TIMELAPSE_RENDERING)

Request shape per `cc2-control/src/mqtt.c:362-372`:

```json
{"id":<rid>,"method":1051,"params":{"url":"<time_lapse_video_url>"}}
```

The reply is immediate (`result.error_code = 0` in ~230 ms) and
carries `result.url` for the eventual `video/<name>.mp4`, but the
MP4 does not exist yet.

**Confirmed success path.** On a fresh `time_lapse_video_status=1`
entry whose raw frames were still on the printer:

1. send `method 1051` with `picture/<name><ts>` as the URL,
2. watch `machine_status.status` transition `1 → 12 → 1`
   (the printer **shows no dialog** during this; the USB-export
   path displays "Generating video" / "Copying video" via
   `sub_status 3020 → 3021`, but a 1051 from LAN runs silent on
   the display — the only user-visible progress is the
   `api_status` stream),
3. re-fetch `method 1036`; the target now has
   `time_lapse_video_status = 2` and the URL rewritten to
   `video/<name>.mp4`,
4. head-probe + GET the new URL as in §3.

On a 100-frame / ~3-second clip, the USB-triggered variant of the
same composite takes ~26 s; the MQTT variant on the same printer
is in the same order of magnitude.

**`sub_status 3022` = no raw frames at the requested path.** Three
separate 1051 runs produced `status 1 → 12 → 1` in under a second
with `3020 → 3022` and no change to `time_lapse_video_status`:

| URL form | Raw frames available? | Dauer |
|---|---|---:|
| `picture/<name><ts>` on 12-day-old entry (deleted at display) | no | 1 s |
| `video/<name>.mp4` on a `status=2` entry | no (post-composite) | 1 ms |
| `picture/<name><ts>` on a `status=2` entry | no (post-composite) | <1 ms |

The reason the window is narrow: the ai_camera composite path
removes the raw-frame directory on success — see
`elegoo/extras/ai_camera/module/util/time_lapse_control.cpp:119-125`
(`cmd = "rm -rf '" + pic_dir + "'"`). After the first composite
(whichever path triggered it), the picture directory is gone and
`method 1051` on that task can only ever hit `3022`.

**Suggestions for the integration:**

- Only send `method 1051` with the `picture/<name><ts>` form —
  the firmware treats `params.url` as a basename and appends
  `.mp4`, so passing a `video/<name>.mp4` form becomes
  `video/<name>.mp4.mp4` and goes to `3022` by construction.
- Do not infer render success from `error_code = 0` or from the
  `status` transition; probe the resulting URL with the same
  head-probe used in §3.
- Treat `sub_status 3022` as a non-fatal "nothing to do" signal,
  not an error.
- Surface a hint when an older `status=1` entry is likely to be
  stale (end_time long before now).

## 5. `method 1038` is history-only

Request shape per `cc2-control/src/mqtt.c:343-346` +
`src/history.h:123-142`:

```json
{"id":<rid>,"method":1038,"params":{"list":["<task_id>", …]}}
```

Reply is `{"result":{"error_code":0}}`; no `machine_status`
transition. On the next `method 1036` the entry is gone and
`result.total` has decreased by one. **The MP4 file on the
printer and the printer's own on-screen time-lapse list are
unchanged.** Measured by downloading the removed entry's URL
immediately after 1038 — the same bytes with the same md5 as the
pre-call baseline, and the owner confirmed the display still
listed the entry.

| Delete path | 1036 history | MP4 on `/opt/usr/video/` | Display list |
|---|:-:|:-:|:-:|
| `method 1038` (MQTT) | removed | kept | kept |
| Display delete (manual) | kept (stale) | removed | removed |

**Treat `method 1038` as UI hygiene, not storage management.**
Only the display delete frees space.

## 6. Printer clock

The printer's clock is **not** synced to real time and the
offset drifts across sessions. On one measured print it was
~8 hours ahead of UTC — the time-lapse filename stamp
`<name>20261026143807` came from a print whose MQTT-side
`begin_time` was `06:38:07Z`. The Elegoo code reads the clock
with `localtime_r`
(`elegoo/extras/ai_camera/module/util/time_lapse_control.cpp:166-172`),
so whichever TZ the system has configured ends up in the
filename. Treat `begin_time`, `end_time` and the filename stamp as
opaque ordering keys only; do not compare them against the HA
host's clock.

## 7. Caveats and suggested changes

Caveats worth keeping in the integration docs:

- **Hand-written vs. slicer-produced files.** The probe files used
  for the 1047 shape run (companion issue) were hand-written G-code
  without a slicer header or thumbnail block, so a refusal there is
  not necessarily a statement about files with a real slicer
  envelope. The 1051 tests above, in contrast, used real sliced
  prints and are not affected.
- **1047 (DELETE_FILE)** answers `error_code 1003` to every
  parameter shape on this firmware and deletes nothing — do not
  wire it up for user-facing deletes. The display delete is the
  only path that removes a file.

Suggested work, happy to split either or both:

- **Documentation PR** against `docs/CC2_PROTOCOL.md`: add
  `method 1036`, `method 1051`, `method 1038`, and the
  `/download?file_name=video/…` path with the semantics above.
- **Feature PR** against `cc2/client.py`: expose
  `history_task_list` as a sensor / diagnostic entity (with the
  three `time_lapse_video_*` columns), and add a time-lapse
  download helper driven by a head-probe (don't trust
  `video_status == 2` alone), plus an optional "render" service
  calling `method 1051` and polling 1036 until the URL goes to
  `video/<name>.mp4`.
