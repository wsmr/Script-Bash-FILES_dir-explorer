# Changelog

All notable changes to this project are documented here.

## [1.0.0] - 2026-08-10

### Added
- Initial release of `dir-explorer.sh`.
- `-d, --depth N` — configurable recursion depth.
- `-e, --exclude-dir NAME` — hide a directory by name, anywhere in the tree.
- `-p, --exclude-path PATH` — hide one specific file or folder, without
  affecting same-named items elsewhere.
- `-f, --exclude-file NAME` — hide a file by exact name.
- `-x, --exclude-ext EXT` — hide files by extension (case-insensitive).
- `-t, --type f|d|both` — restrict listings to files, folders, or both.
- `--empty` — list empty folders in a separate section.
- `-s, --search TEXT` / `--exact` — filter the listing to matching names,
  by substring, glob pattern, or exact match.
- `--git-info` — print the current branch and origin remote.
- `--opt=value` long-option syntax, `--` end-of-options marker.
- Full `-h/--help` and `-v/--version`.

### Notes
- Verified read-only via a before/after checksum diff (structure, content
  hashes, permissions, and mtimes) across every flag combination against a
  synthetic test project — no file or folder was modified.
