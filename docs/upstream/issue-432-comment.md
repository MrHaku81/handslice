Hi — ran this on a real CC2 today, happy to drop the measurements in.

**Firmware (from `method 1001` software_version):**
- `ota_version = 02.01.01.07`
- `mcu_version` and `soc_version` reported empty by the printer

**Setup:**
- Centauri Carbon 2 Combo, Access-Code pairing (`token_status = 1`,
  `lan_status = 1`), MQTT 1883 + chunked HTTP PUT 80. Printer idle
  throughout.
- Note on the clock: my printer's clock is set (UTC+1), so I
  couldn't test the never-set / 1970 case. As a pure observation
  (no cause claimed): the `create_time` field returned by `method
  1046` for the test file I had just uploaded was about 1 h 33 min
  behind real UTC at the time. Printer was in LAN-only mode.

### What I sent

Payload exactly per the request shape documented in `CC2_PROTOCOL.md`
and used by `cc2/client.py#delete_file`:

```json
{"id":<rid>,"method":1047,"params":{"storage_media":"local",
                                    "filename":"<name>"}}
```

Two cases, same session, back-to-back.

#### Case A — file that exists (uploaded by me a minute earlier)

Before: `method 1044` on `storage_media="local"` lists 24 files, the
test file appears exactly once (verified by exact string match).

Request:

```json
{"id":<rid>,"method":1047,"params":{"storage_media":"local",
                                    "filename":"handslice_delete_test_<ts>.gcode"}}
```

Printer reply, ~13 ms round-trip:

```json
{"id":<rid>,"method":1047,"result":{"error_code":1003}}
```

After the reply, re-listing with `method 1044` returns 24 files
again, the test file is **still there**, every other file hash
unchanged. I confirmed on the printer display that the file was
still visible.

#### Case B — file that does not exist

Request:

```json
{"id":<rid>,"method":1047,"params":{"storage_media":"local",
                                    "filename":"handslice_does_not_exist_<ts>.gcode"}}
```

Reply, ~10 ms:

```json
{"id":<rid>,"method":1047,"result":{"error_code":1003}}
```

List 24/24 identical before and after.

### Control test

The same file could be deleted without problems via the printer's
touchscreen, so the file wasn't locked or protected — only the LAN
delete via 1047 does nothing.

### Reading

Same `error_code=1003` for an existing file and a non-existing one,
both ~10–13 ms round-trip, nothing deleted in either case. Earlier
in the session, `method 1045 GET_FILE_THUMBNAIL` also returned
`error_code=1003` on this firmware. So I'd lean towards "1003 is
this firmware's generic 'not available / not handled' bucket",
**as a hypothesis** — I don't have an authoritative mapping for 1003
in CC2_PROTOCOL.md and I don't want to assert it as doc.

Practically, for `delete_file` on 02.01.01.07 this means:

- The envelope the integration already uses (`result.error_code`) is
  what the printer sends — the `cc2/client.py` inference is
  consistent with what we see. 
- `error_code == 0` would be "the printer accepted and probably
  deleted"; the current comment in client.py (`"0 means printer did
  not refuse, not proof of deletion"`) matches the behaviour.
- `error_code != 0` on this firmware is `1003`, not the hinted
  `1007 FILE_DELETE_FAILED` from the reference table. The printer
  does not distinguish "file missing" from "method not handled"
  here.
- Re-listing via 1044 (as `cleanup_files` does) is the only
  reliable confirmation; the reply alone is not enough.

### Side note on the video question

Not from the delete thread itself, but it came up during the same
session: on this firmware, `method 1044` for `storage_media="local"`
/ `"sdcard"` / `"udisk"` does **not** list the two timelapse videos
that are visible under the display's camera tab. Timelapse recording
works (triggered via `config.delay_video=true` in `method 1020`),
but the recorded videos don't surface in `1044` and don't appear to
have a documented LAN retrieval path yet — `elegoo-link` has
`EXPORT_TIMELAPSE_VIDEO = 1045` commented out as "interface not
designed yet", and `1045` is actually `GET_FILE_THUMBNAIL` in the
integration's constants. On this firmware, the two videos are
display-only / USB export only.

Happy to re-run with any extra variants (`storage_media="sdcard"`,
different filename encodings, extra fields) you'd like checked —
same CC2 is still paired and idle.
