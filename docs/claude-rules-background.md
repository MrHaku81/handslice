# Background to the CLAUDE.md rules

`CLAUDE.md` holds the binding rules. This file holds the reasons and
examples that were moved out of it on 2026-11-06, so that every session
starts with less to read. Nothing here adds or changes a rule.

## Credentials and scrub checks (§2)

The ban covers search patterns too, because a value on a command line
ends up in the terminal log.

- Wrong: `grep -c "<access-code-wert>" datei`. The value appears on the
  command line and in the terminal log.
- Right: a Python script reads the value internally from `.env` and
  prints only the hit count.

## Focus navigation (§5)

The rule exists for accessibility. A side benefit is that the app also
works on Android TV and on tablets with a keyboard.

## English as project language (§5)

The switch on 2026-10-31 lets the international community read along
and contribute.
