# 2026-04-28 default table output

## Summary

Changed `ddstartup` commands to render human-readable table output by default and reserved JSON for explicit `-o json` use.

## What Changed

- `setup`, `enable`, `disable`, `status`, and `remove` now print key/value tables by default
- `logs` now prints a table that includes the requested line count and log payload by default
- every command accepts `-o json` for machine-readable scripting

## Why

The skill is mostly used directly in a terminal, so the default output should be easy to scan without forcing the user to parse JSON by eye.
