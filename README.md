# 🗂️ dir-explorer

> A fast, fully configurable, **read-only** Bash script that lists the files and folders in one or more directories — with per-run control over exclusions, depth, type, and search, instead of a wall of `node_modules`.

[![Shell](https://img.shields.io/badge/shell-bash-informational?style=flat-square&logo=gnu-bash)](https://www.gnu.org/software/bash/)
[![Platform](https://img.shields.io/badge/platform-macOS%20%7C%20Linux-lightgrey?style=flat-square)](#-compatibility)
[![License](https://img.shields.io/badge/license-MIT-green?style=flat-square)](LICENSE)
[![Version](https://img.shields.io/badge/version-1.0.0-blue?style=flat-square)](CHANGELOG.md)
[![Read--only](https://img.shields.io/badge/filesystem-read--only-brightgreen?style=flat-square)](#-safety)

---

## ✨ Features

- **Configurable exclusions** — by directory name (anywhere in the tree), by exact path (one specific location), by exact filename, or by extension
- **Configurable depth** — unlimited, or capped at N levels
- **Files-only / folders-only / both** — one flag, applies to any listing
- **Search mode** — contains, your own glob pattern, or exact match, optionally type-filtered
- **Empty-folder detection** — a dedicated section, on request
- **Multiple targets in one run** — scan several folders at once
- **Strictly read-only** — never creates, edits, moves, or deletes anything (see [Safety](#-safety))
- **No project-specific logic baked in** — works on any project, any folder

---

## 📦 Installation

**1. Clone the repository**
```bash
git clone <your-repo-url>.git
cd dir-explorer
```

**2. Make it executable**
```bash
chmod +x dir-explorer.sh
```

**3. Run it directly, or drop it on your `PATH`**
```bash
./dir-explorer.sh --help

# optional: make it available everywhere
cp dir-explorer.sh /usr/local/bin/dir-explorer
```

---

## 🚀 Usage

```bash
dir-explorer.sh [OPTIONS] [PATH...]
```

If no `PATH` is given, the **current directory** is used. Run it as
`./dir-explorer.sh` or `bash dir-explorer.sh` — see [Compatibility](#-compatibility)
for why `zsh dir-explorer.sh` isn't supported.

---

## 🔧 Options

| Flag | Description |
|---|---|
| `-d, --depth N` | Limit recursion to N levels deep (default: unlimited) |
| `-e, --exclude-dir NAME` | Hide any folder named exactly `NAME`, anywhere in the tree, contents included (repeatable) |
| `-p, --exclude-path PATH` | Hide one specific file/folder at `PATH` only — doesn't affect same-named items elsewhere (repeatable) |
| `-f, --exclude-file NAME` | Hide any file whose name is exactly `NAME` (repeatable) |
| `-x, --exclude-ext EXT` | Hide files with extension `EXT`, no dot, case-insensitive (repeatable) |
| `-t, --type f\|d\|both` | Show only files, only folders, or both (default: `both`) |
| `--empty` | Also list empty folders, in a separate section |
| `--git-info` | Print the current git branch + origin remote first |
| `-s, --search TEXT` | Only show entries whose name contains `TEXT` (case-insensitive); include `*`/`?` for a custom glob |
| `--exact` | With `--search`, require an exact, case-sensitive match |
| `-h, --help` | Show help |
| `-v, --version` | Show version |

`--opt=value` works everywhere `--opt value` does. `--` stops flag parsing.

---

## 📋 Examples

```bash
# Everything under the current folder
./dir-explorer.sh

# Specific folders
./dir-explorer.sh src public

# Common noise excluded, plus an empty-folders section
./dir-explorer.sh -e node_modules -e .git -e public -f .DS_Store -x log --empty

# One specific folder hidden, without excluding every folder that shares its name
./dir-explorer.sh -p ios/App/App/Assets

# One level deep only — e.g. a build output folder
./dir-explorer.sh -d 1 ./android/app/build

# Folders only, unlimited depth — e.g. an assets tree
./dir-explorer.sh -t d ./src/assets/images/games

# Search: files with "config" in the name, anywhere
./dir-explorer.sh -s config -t f

# Search: your own glob pattern
./dir-explorer.sh --search "*.test.*" -t f

# Search: the file literally named "Button", case-sensitive, under src/
./dir-explorer.sh -s Button --exact -t f src

# Git branch + remote header, plus a scan
./dir-explorer.sh --git-info -e node_modules .
```

### `-e` vs `-p` — the two exclude modes

- **`-e/--exclude-dir`** matches by **name**, anywhere: `-e node_modules`
  hides every `node_modules` folder in the tree, however many copies exist.
  Use it for generic noise: `node_modules`, `.git`, `public`, build caches.
- **`-p/--exclude-path`** matches one **exact location**: `-p
  ios/App/App/Assets` hides only that folder, even if an unrelated `Assets`
  folder exists elsewhere and should stay visible.

Both hide the folder itself *and* everything inside it.

---

## 🖥️ Sample Output

```
--- . ---
./README.md
./src/
./src/components/
./src/components/Button.tsx
./src/index.ts

--- EMPTY FOLDERS ---
./src/emptyDir/
```

---

## 🔒 Safety

This script is **strictly read-only**. It only ever calls `find`, `sort`,
`basename`, `tr`, `printf`, and — only with `--git-info` — the read-only
commands `git branch`, `git remote get-url`, and `git rev-parse`. There is
no `rm`, `mv`, `cp`, `chmod`, `chown`, `touch`, `sed -i`, or arbitrary output
redirection anywhere in the script.

This was verified empirically, not just by design: a full before/after
checksum (directory structure, file content hashes, permissions, and
mtimes) taken across every flag combination against a test project came
back byte-for-byte identical.

Confirm it yourself in a few seconds:
```bash
grep -nE '\b(rm|mv|cp|chmod|chown|touch|dd|shred)\b' dir-explorer.sh
```
That only ever matches the safety comment at the top of the file, which
names those commands to say they're *not* used.

---

## ⚙️ Persistent defaults

To avoid retyping the same exclusions every time, edit the arrays near the
top of the script:

```bash
EXCLUDE_DIRS=(node_modules .git public)
EXCLUDE_FILES=(.DS_Store package-lock.json)
```

Flags on the command line add to these, they don't replace them.

---

## 🧩 Compatibility

| Environment | Status |
|---|---|
| Bash (Linux) | ✅ Tested (5.2) |
| Bash (macOS, incl. the old built-in 3.2) | ✅ Written to avoid anything newer than bash 3.2 |
| Invoked as `zsh dir-explorer.sh` | ❌ Not supported — confirmed to break; always run via `./dir-explorer.sh` or `bash dir-explorer.sh` |

---

## ⚠️ Known limitations

- `--exclude-ext` matches only the last dot-segment (`archive.tar.gz` → `gz`, not `tar.gz`).
- Symlinks are listed but not followed (no infinite loops on circular links).
- Filenames containing a literal newline character (very rare) may not display perfectly, though exclusion/search still work correctly on them.
- Depth, type, and search settings apply globally per run — there's no per-subfolder rule set within a single invocation. Run the script again with different flags for a different subfolder.

---

## 🤝 Contributing

Issues and pull requests are welcome.

1. Fork the repository
2. Create your feature branch: `git checkout -b feature/my-flag`
3. Commit your changes: `git commit -m 'feat: add my-flag'`
4. Push to the branch: `git push origin feature/my-flag`
5. Open a Pull Request

---

## 📌 Changelog

See [CHANGELOG.md](CHANGELOG.md) for version history.

## 📄 License

MIT — see [LICENSE](LICENSE) for full terms.
