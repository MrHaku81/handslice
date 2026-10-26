# Draft comment for danielcherubini/elegoo-homeassistant#432

Ran `scripts/cc2_probe_delete.py` from `v2.16.0-beta.2` with `--run`
on real hardware, firmware `02.01.01.07`. The twelve leftover probe
files it uploaded (one preflight from the dry run plus eleven from
`--run`) were removed via the printer's touchscreen afterwards.

```
==============================================================================
CC2 METHOD 1047 (DELETE_FILE) PARAMETER-SHAPE PROBE
==============================================================================
captured at      : 2026-10-26T10:28:50+01:00
mode             : run
printer ip       : <printer-ip>
serial           : <cc2-sn>
serial source    : --serial flag
printer name     : None
model            : Centauri Carbon 2
firmware         : 02.01.01.07   (from 1001 software_version.ota_version)
token_status     : unknown (no discovery round-trip; --serial was given)   (1 = access code required)
access code      : supplied
upload port      : 80
variants         : 11 answered, 0 got NO REPLY AT ALL (of 11 attempted)

HOW TO READ THIS
  * The probe files are hand-written G-code, not slicer output. Whether this printer accepts a bare hand-written body for upload AND for delete is itself unmeasured — real sliced files carry a slicer header and a thumbnail block. A 1003 against one of these files is therefore ambiguous between 'wrong parameter shape' and 'this file is not deletable'. Names end in .gcode and the bodies are non-trivially sized to keep the files as plausible as a hand-written file can be.
  * The alternative reading of 1003 is NOT excluded by this script: the reporter of #432 also saw method 1045 answer 1003 for one file in the same session, and suggested 1003 may be this firmware's generic 'not available / not handled' bucket. That reading is equally untested. The discriminating signal is whether ANY variant both answers error_code 0 and makes its own file disappear from the next 1044; if nothing does, this report says so and the alternative reading stands.
  * Every delete here targets a file this script uploaded itself. No pre-existing user file was touched, and the printer was checked idle with a filename guard before anything was sent.

Every variant was measured against ITS OWN file, uploaded by this run; one variant's success cannot contaminate another's.
------------------------------------------------------------------------------
--- variant 1: local_filename — what we ship today (1044's storage_media + 1046's key)
file            : cc2_probe_local_filename_a11642c5.gcode
uploaded        : 8244 bytes, md5 1ce610808e2cb8ffec92d43279de4a6b
request         : {"id": <auto>, "method": 1047, "params": {"storage_media": "local", "filename": "cc2_probe_local_filename_a11642c5.gcode"}}
raw reply       : {"id": 6, "method": 1047, "result": {"error_code": 1003}}
error_code      : 1003
status          : sent
elapsed         : 10.8 ms
still_listed    : True
listing size    : 27 entries
verdict         : refused (error_code 1003), file still listed

--- variant 2: local_file_name — THE HYPOTHESIS: 1045 works being sent file_name
file            : cc2_probe_local_file_name_c91794d7.gcode
uploaded        : 8244 bytes, md5 1ce610808e2cb8ffec92d43279de4a6b
request         : {"id": <auto>, "method": 1047, "params": {"storage_media": "local", "file_name": "cc2_probe_local_file_name_c91794d7.gcode"}}
raw reply       : {"id": 10, "method": 1047, "result": {"error_code": 1003}}
error_code      : 1003
status          : sent
elapsed         : 20.0 ms
still_listed    : True
listing size    : 28 entries
verdict         : refused (error_code 1003), file still listed

--- variant 3: local_filename_path — 1044 sends a path; 1047 may want one too
file            : cc2_probe_local_filename_path_e4bce5b0.gcode
uploaded        : 8244 bytes, md5 1ce610808e2cb8ffec92d43279de4a6b
request         : {"id": <auto>, "method": 1047, "params": {"storage_media": "local", "filename": "cc2_probe_local_filename_path_e4bce5b0.gcode", "path": "/"}}
raw reply       : {"id": 13, "method": 1047, "result": {"error_code": 1003}}
error_code      : 1003
status          : sent
elapsed         : 11.2 ms
still_listed    : True
listing size    : 29 entries
verdict         : refused (error_code 1003), file still listed

--- variant 4: local_file_name_path — file_name plus path
file            : cc2_probe_local_file_name_path_8b21691e.gcode
uploaded        : 8244 bytes, md5 1ce610808e2cb8ffec92d43279de4a6b
request         : {"id": <auto>, "method": 1047, "params": {"storage_media": "local", "file_name": "cc2_probe_local_file_name_path_8b21691e.gcode", "path": "/"}}
raw reply       : {"id": 17, "method": 1047, "result": {"error_code": 1003}}
error_code      : 1003
status          : sent
elapsed         : 10.1 ms
still_listed    : True
listing size    : 30 entries
verdict         : refused (error_code 1003), file still listed

--- variant 5: bare_filename — is storage_media itself the offending key?
file            : cc2_probe_bare_filename_4b2c6afa.gcode
uploaded        : 8244 bytes, md5 1ce610808e2cb8ffec92d43279de4a6b
request         : {"id": <auto>, "method": 1047, "params": {"filename": "cc2_probe_bare_filename_4b2c6afa.gcode"}}
raw reply       : {"id": 20, "method": 1047, "result": {"error_code": 1003}}
error_code      : 1003
status          : sent
elapsed         : 11.1 ms
still_listed    : True
listing size    : 31 entries
verdict         : refused (error_code 1003), file still listed

--- variant 6: control_empty — CONTROL: what a bare request answers (its file is never named in it)
file            : cc2_probe_control_empty_f37ccc43.gcode
uploaded        : 8244 bytes, md5 1ce610808e2cb8ffec92d43279de4a6b
request         : {"id": <auto>, "method": 1047, "params": {}}
raw reply       : {"id": 24, "method": 1047, "result": {"error_code": 1003}}
error_code      : 1003
status          : sent
elapsed         : 12.6 ms
still_listed    : True
listing size    : 32 entries
note            : this request names NO file, so still_listed=true is expected whatever the reply says; read only the error_code.
verdict         : refused (error_code 1003), file still listed

--- variant 7: sdcard_filename — sd-card spelled the way the HTTP download paths spell it
file            : cc2_probe_sdcard_filename_186d7bb2.gcode
uploaded        : 8244 bytes, md5 1ce610808e2cb8ffec92d43279de4a6b
request         : {"id": <auto>, "method": 1047, "params": {"storage_media": "sdcard", "filename": "cc2_probe_sdcard_filename_186d7bb2.gcode"}}
raw reply       : {"id": 27, "method": 1047, "result": {"error_code": 1003}}
error_code      : 1003
status          : sent
elapsed         : 10.0 ms
still_listed    : True
listing size    : 33 entries
verdict         : refused (error_code 1003), file still listed

--- variant 8: sdcard_file_name — same, underscored key
file            : cc2_probe_sdcard_file_name_5bcbe9ce.gcode
uploaded        : 8244 bytes, md5 1ce610808e2cb8ffec92d43279de4a6b
request         : {"id": <auto>, "method": 1047, "params": {"storage_media": "sdcard", "file_name": "cc2_probe_sdcard_file_name_5bcbe9ce.gcode"}}
raw reply       : {"id": 31, "method": 1047, "result": {"error_code": 1003}}
error_code      : 1003
status          : sent
elapsed         : 9.5 ms
still_listed    : True
listing size    : 34 entries
verdict         : refused (error_code 1003), file still listed

--- variant 9: udisk_filename — u-disk spelled the way the HTTP download paths spell it
file            : cc2_probe_udisk_filename_f2783b77.gcode
uploaded        : 8244 bytes, md5 1ce610808e2cb8ffec92d43279de4a6b
request         : {"id": <auto>, "method": 1047, "params": {"storage_media": "udisk", "filename": "cc2_probe_udisk_filename_f2783b77.gcode"}}
raw reply       : {"id": 34, "method": 1047, "result": {"error_code": 1003}}
error_code      : 1003
status          : sent
elapsed         : 10.6 ms
still_listed    : True
listing size    : 35 entries
verdict         : refused (error_code 1003), file still listed

--- variant 10: sd_card_filename — sd-card spelled the way the protocol doc's storage table spells it
file            : cc2_probe_sd_card_filename_72c2db59.gcode
uploaded        : 8244 bytes, md5 1ce610808e2cb8ffec92d43279de4a6b
request         : {"id": <auto>, "method": 1047, "params": {"storage_media": "sd-card", "filename": "cc2_probe_sd_card_filename_72c2db59.gcode"}}
raw reply       : {"id": 38, "method": 1047, "result": {"error_code": 1003}}
error_code      : 1003
status          : sent
elapsed         : 10.9 ms
still_listed    : True
listing size    : 36 entries
verdict         : refused (error_code 1003), file still listed

--- variant 11: u_disk_filename — u-disk spelled the way the protocol doc's storage table spells it
file            : cc2_probe_u_disk_filename_123c452e.gcode
uploaded        : 8244 bytes, md5 1ce610808e2cb8ffec92d43279de4a6b
request         : {"id": <auto>, "method": 1047, "params": {"storage_media": "u-disk", "filename": "cc2_probe_u_disk_filename_123c452e.gcode"}}
raw reply       : {"id": 42, "method": 1047, "result": {"error_code": 1003}}
error_code      : 1003
status          : sent
elapsed         : 13.8 ms
still_listed    : True
listing size    : 37 entries
verdict         : refused (error_code 1003), file still listed

------------------------------------------------------------------------------
CONCLUSION
  EVERY VARIANT ANSWERED IDENTICALLY (error_code 1003) and none of them removed its own file (all 11 confirming 1044 read(s) saw the variant's own file still listed). That is a real finding. What it means: on this firmware 1003 is not about the parameter key at all — 1047 is simply not served, or 1003 is its generic 'not available / not handled' answer. The key-name hypothesis is not supported by this capture.

  LEFTOVERS this run could not delete (11), remove them from the printer's UI:
    cc2_probe_bare_filename_4b2c6afa.gcode
    cc2_probe_control_empty_f37ccc43.gcode
    cc2_probe_local_file_name_c91794d7.gcode
    cc2_probe_local_file_name_path_8b21691e.gcode
    cc2_probe_local_filename_a11642c5.gcode
    cc2_probe_local_filename_path_e4bce5b0.gcode
    cc2_probe_sd_card_filename_72c2db59.gcode
    cc2_probe_sdcard_file_name_5bcbe9ce.gcode
    cc2_probe_sdcard_filename_186d7bb2.gcode
    cc2_probe_u_disk_filename_123c452e.gcode
    cc2_probe_udisk_filename_f2783b77.gcode
==============================================================================
```
