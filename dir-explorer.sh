#!/usr/bin/env bash
#
# dir-explorer.sh — configurable, read-only file & folder explorer
#
# Lists files and folders under one or more target directories, with
# configurable exclusions (by directory name, exact filename, or file
# extension), configurable recursion depth, a files-only/folders-only
# switch, and an optional search mode that shows only entries whose name
# matches a given piece of text or pattern.
#
# SAFETY — this script is strictly READ-ONLY:
#   - It never creates, edits, moves, renames, or deletes any file or folder.
#   - The only external commands it ever calls are: find, sort, basename,
#     tr, printf, and (only if you pass --git-info) the read-only commands
#     `git branch --show-current`, `git remote get-url origin`, and
#     `git rev-parse --is-inside-work-tree`.
#   - There is no rm, mv, cp, chmod, chown, touch, sed -i, or output
#     redirection to arbitrary files anywhere below. Feel free to read the
#     whole file (well under 500 lines, mostly comments/help text) or grep
#     it yourself to confirm:
#       grep -nE '\brm\b|\bmv\b|\bcp\b|\bchmod\b|\bchown\b|\btouch\b' dir-explorer.sh
#
# Run it as ./dir-explorer.sh (after `chmod +x`) or as `bash dir-explorer.sh`.
# Both let the shebang above pick a real bash, which is what this is written
# and tested against. Do NOT run it as `zsh dir-explorer.sh` — forcing zsh to
# interpret it directly does not work (confirmed: it breaks on the dynamic
# find-argument arrays), even though plain bash is zsh's default on macOS.
#
# USAGE:
#   ./dir-explorer.sh [OPTIONS] [PATH...]
#
# Run with -h/--help for the full flag reference and examples.

set -o pipefail

VERSION="1.0.0"
SCRIPT_NAME="$(basename -- "$0")"

# ---------------------------------------------------------------------------
# Defaults — edit these if you want persistent behaviour without typing
# flags every time. Everything here can still be overridden or extended
# from the command line on any given run.
# ---------------------------------------------------------------------------
MAX_DEPTH=0                  # 0 = unlimited
EXCLUDE_DIRS=()               # by NAME, anywhere in the tree: (node_modules .git)
EXCLUDE_PATHS=()              # by EXACT PATH, this location only: (ios/App/App/Assets)
EXCLUDE_FILES=()              # e.g. (.DS_Store package-lock.json)
EXCLUDE_EXTS=()               # e.g. (log map)
SEARCH_TYPE="both"            # f | d | both
SEARCH_TEXT=""
EXACT_MATCH=0
SHOW_EMPTY=0
SHOW_GIT_INFO=0
FOLDER_ARGS=()
PRUNE_ARGS=()
EXCLUDE_PATHS_NORM=()

usage() {
  cat <<EOF
dir-explorer.sh v${VERSION} — configurable, read-only file & folder explorer

USAGE:
  ${SCRIPT_NAME} [OPTIONS] [PATH...]

  PATH...    One or more folders to scan (default: current directory).

LISTING OPTIONS:
  -d, --depth N            Limit recursion to N levels deep (default: unlimited)
  -e, --exclude-dir NAME   Hide any directory named exactly NAME, anywhere in
                            the tree, including everything inside it
                            (repeatable: -e node_modules -e .git)
  -p, --exclude-path PATH  Hide one specific file or folder at PATH only
                            (and everything inside it, if it's a folder) —
                            unlike -e, this does NOT affect other items that
                            happen to share the same name elsewhere
                            (repeatable: -p ios/App/App/Assets)
  -f, --exclude-file NAME  Hide any file whose name is exactly NAME
                            (repeatable)
  -x, --exclude-ext EXT    Hide files with extension EXT, e.g. log, map, png —
                            no leading dot, case-insensitive (repeatable)
  -t, --type f|d|both      Only show files (f), only folders (d), or both
                            (default: both)
      --empty              Also list empty folders in a separate section
      --git-info            Print the current git branch and origin remote
                            first (skipped quietly if not inside a git repo)

SEARCH OPTIONS (show only matching entries, instead of the full listing):
  -s, --search TEXT         Only show files/folders whose name contains TEXT
                            (case-insensitive). Include * or ? in TEXT to use
                            it as your own glob pattern instead of "contains".
      --exact                Require an exact, case-sensitive name match
                            instead of "contains" — use together with --search

OTHER:
  -h, --help                 Show this help and exit
  -v, --version                Show version and exit

EXAMPLES:
  ${SCRIPT_NAME}
  ${SCRIPT_NAME} src public
  ${SCRIPT_NAME} -d 1 ./android/app/build
  ${SCRIPT_NAME} -t d ./src/assets/images/games
  ${SCRIPT_NAME} -e node_modules -e .git -e public -f .DS_Store -x log --empty
  ${SCRIPT_NAME} -e node_modules -p ios/App/App/Assets -p android/app/build
  ${SCRIPT_NAME} -s config -t f
  ${SCRIPT_NAME} --search "*.test.*" -t f
  ${SCRIPT_NAME} -s Button --exact -t f src
  ${SCRIPT_NAME} --git-info -e node_modules .

Every option is repeatable and combinable. Folders are always listed
alphabetically with a trailing / so you can tell them apart from files.

SAFETY: read-only. Never creates, edits, moves, or deletes anything.
EOF
}

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

require_value() {
  # $1 = flag name (for the error message), $2 = the value that follows it
  if [[ -z "$2" ]]; then
    echo "Error: '$1' requires a value" >&2
    exit 1
  fi
}

to_lower() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]'
}

# Prints a file's extension per common convention: a leading single dot
# (as in .env, .gitignore) does NOT count as an extension, and multi-dot
# names only count the last segment (archive.tar.gz -> gz). Prints nothing
# if there is no extension.
get_ext() {
  local name="$1" stripped="$1"
  [[ "$stripped" == .* ]] && stripped="${stripped#.}"
  if [[ "$stripped" == *.* ]]; then
    printf '%s' "${stripped##*.}"
  fi
}

is_excluded_file() {
  local base="$1" ef ee ext
  for ef in "${EXCLUDE_FILES[@]}"; do
    [[ "$base" == "$ef" ]] && return 0
  done
  if [[ ${#EXCLUDE_EXTS[@]} -gt 0 ]]; then
    ext="$(get_ext "$base")"
    if [[ -n "$ext" ]]; then
      ext="$(to_lower "$ext")"
      for ee in "${EXCLUDE_EXTS[@]}"; do
        [[ "$ext" == "$(to_lower "$ee")" ]] && return 0
      done
    fi
  fi
  return 1
}

name_matches_search() {
  local base="$1" base_cmp pattern_cmp

  if [[ "$EXACT_MATCH" -eq 1 ]]; then
    [[ "$base" == "$SEARCH_TEXT" ]]
    return
  fi

  base_cmp="$(to_lower "$base")"
  pattern_cmp="$(to_lower "$SEARCH_TEXT")"

  case "$pattern_cmp" in
    *[*?]*) [[ "$base_cmp" == $pattern_cmp ]] ;;
    *)      [[ "$base_cmp" == *"$pattern_cmp"* ]] ;;
  esac
}

# Strips a single leading "./" and a single trailing "/" so that a path can
# be compared consistently no matter how the user or find happened to write
# it (e.g. "./ios/Assets", "ios/Assets" and "ios/Assets/" all normalize the
# same way).
normalize_path() {
  local p="$1"
  p="${p#./}"
  p="${p%/}"
  printf '%s' "$p"
}

# Sets the global EXCLUDE_PATHS_NORM to the normalized form of every
# --exclude-path value.
build_exclude_paths_norm() {
  EXCLUDE_PATHS_NORM=()
  local p
  for p in "${EXCLUDE_PATHS[@]}"; do
    EXCLUDE_PATHS_NORM+=( "$(normalize_path "$p")" )
  done
}

# True if the given (already-normalized) path is exactly one of
# EXCLUDE_PATHS_NORM, or lives inside one of them.
is_excluded_path() {
  local path_norm="$1" ep
  for ep in "${EXCLUDE_PATHS_NORM[@]}"; do
    [[ -z "$ep" ]] && continue
    [[ "$path_norm" == "$ep" || "$path_norm" == "$ep"/* ]] && return 0
  done
  return 1
}

# Sets the global PRUNE_ARGS to the find(1) arguments that hide every
# directory named in EXCLUDE_DIRS, anywhere in the tree, together with
# everything inside it. Left empty if EXCLUDE_DIRS is empty.
#
# NOTE: EXCLUDE_PATHS (exact-path excludes) are deliberately NOT handled
# here — they're checked in the shell-side loop in list_one_target /
# list_empty_dirs_for_target via is_excluded_path instead, since a specific
# path (as opposed to a name) isn't something find's -prune can match
# reliably regardless of how the target root itself was written.
build_prune_args() {
  PRUNE_ARGS=()
  local d first=1
  [[ ${#EXCLUDE_DIRS[@]} -eq 0 ]] && return
  PRUNE_ARGS+=( '(' -type d '(' )
  for d in "${EXCLUDE_DIRS[@]}"; do
    if [[ $first -eq 1 ]]; then
      PRUNE_ARGS+=( -name "$d" )
      first=0
    else
      PRUNE_ARGS+=( -o -name "$d" )
    fi
  done
  PRUNE_ARGS+=( ')' ')' -prune -o )
}

# ---------------------------------------------------------------------------
# Listing
# ---------------------------------------------------------------------------

list_one_target() {
  local target="$1"
  local -a find_args=("$target" -mindepth 1)
  [[ "$MAX_DEPTH" -gt 0 ]] && find_args+=( -maxdepth "$MAX_DEPTH" )
  find_args+=( "${PRUNE_ARGS[@]}" -print0 )

  local path base is_dir keep lines=""
  while IFS= read -r -d '' path; do
    base="$(basename -- "$path")"
    if [[ -d "$path" ]]; then is_dir=1; else is_dir=0; fi
    keep=1

    if [[ ${#EXCLUDE_PATHS_NORM[@]} -gt 0 ]] && is_excluded_path "$(normalize_path "$path")"; then
      keep=0
    fi

    [[ "$SEARCH_TYPE" == "f" && $is_dir -eq 1 ]] && keep=0
    [[ "$SEARCH_TYPE" == "d" && $is_dir -eq 0 ]] && keep=0

    if [[ $keep -eq 1 && $is_dir -eq 0 ]] && is_excluded_file "$base"; then
      keep=0
    fi

    if [[ $keep -eq 1 && -n "$SEARCH_TEXT" ]] && ! name_matches_search "$base"; then
      keep=0
    fi

    if [[ $keep -eq 1 ]]; then
      if [[ $is_dir -eq 1 ]]; then
        lines+="${path}/"$'\n'
      else
        lines+="${path}"$'\n'
      fi
    fi
  done < <(find "${find_args[@]}")

  if [[ -z "$lines" ]]; then
    echo "  (no matching entries)"
  else
    printf '%s' "$lines" | sort
  fi
}

list_empty_dirs_for_target() {
  local target="$1"
  local -a find_args=("$target" -mindepth 1)
  [[ "$MAX_DEPTH" -gt 0 ]] && find_args+=( -maxdepth "$MAX_DEPTH" )
  # NOTE: the prune clause MUST come before -type d -empty here, not after —
  # otherwise a non-empty excluded directory (e.g. a full node_modules) would
  # fail the -empty test before find ever reaches -prune, and find would
  # keep descending into it looking for empty subfolders. Putting prune
  # first means excluded directories are skipped entirely, regardless of
  # whether they themselves are empty.
  find_args+=( "${PRUNE_ARGS[@]}" -type d -empty -print0 )

  local path lines=""
  while IFS= read -r -d '' path; do
    if [[ ${#EXCLUDE_PATHS_NORM[@]} -gt 0 ]] && is_excluded_path "$(normalize_path "$path")"; then
      continue
    fi
    lines+="${path}/"$'\n'
  done < <(find "${find_args[@]}")

  if [[ -z "$lines" ]]; then
    echo "  (none found)"
  else
    printf '%s' "$lines" | sort
  fi
}

print_git_info() {
  if ! command -v git >/dev/null 2>&1; then
    echo "Note: --git-info was set, but git isn't available." >&2
    return
  fi
  if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "Note: --git-info was set, but this doesn't look like a git repository." >&2
    return
  fi
  local branch remote
  branch="$(git branch --show-current 2>/dev/null)"
  remote="$(git remote get-url origin 2>/dev/null)"
  echo "Branch: ${branch:-(none)}"
  echo "Repo: ${remote:-(no origin remote)}"
  echo ""
}

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------

# Normalize --opt=value into --opt value so both forms work.
_norm_args=()
for _a in "$@"; do
  case "$_a" in
    --*=*) _norm_args+=("${_a%%=*}" "${_a#*=}") ;;
    *) _norm_args+=("$_a") ;;
  esac
done
set -- "${_norm_args[@]}"
unset _norm_args _a

while [[ $# -gt 0 ]]; do
  case "$1" in
    -d|--depth)
      require_value "$1" "$2"; MAX_DEPTH="$2"; shift 2 ;;
    -e|--exclude-dir)
      require_value "$1" "$2"; EXCLUDE_DIRS+=("$2"); shift 2 ;;
    -p|--exclude-path)
      require_value "$1" "$2"; EXCLUDE_PATHS+=("$2"); shift 2 ;;
    -f|--exclude-file)
      require_value "$1" "$2"; EXCLUDE_FILES+=("$2"); shift 2 ;;
    -x|--exclude-ext)
      require_value "$1" "$2"; EXCLUDE_EXTS+=("$2"); shift 2 ;;
    -t|--type)
      require_value "$1" "$2"; SEARCH_TYPE="$2"; shift 2 ;;
    -s|--search)
      require_value "$1" "$2"; SEARCH_TEXT="$2"; shift 2 ;;
    --exact)
      EXACT_MATCH=1; shift ;;
    --empty)
      SHOW_EMPTY=1; shift ;;
    --git-info)
      SHOW_GIT_INFO=1; shift ;;
    -h|--help)
      usage; exit 0 ;;
    -v|--version)
      echo "${SCRIPT_NAME} v${VERSION}"; exit 0 ;;
    --)
      shift; FOLDER_ARGS+=("$@"); break ;;
    -*)
      echo "Error: unknown option '$1'" >&2
      echo "Run '${SCRIPT_NAME} --help' for usage." >&2
      exit 1 ;;
    *)
      FOLDER_ARGS+=("$1"); shift ;;
  esac
done

[[ ${#FOLDER_ARGS[@]} -eq 0 ]] && FOLDER_ARGS=(".")

if ! [[ "$MAX_DEPTH" =~ ^[0-9]+$ ]]; then
  echo "Error: --depth must be a non-negative integer (got '$MAX_DEPTH')" >&2
  exit 1
fi

case "$SEARCH_TYPE" in
  f|d|both) ;;
  *)
    echo "Error: --type must be one of: f, d, both (got '$SEARCH_TYPE')" >&2
    exit 1 ;;
esac

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

main() {
  build_prune_args
  build_exclude_paths_norm

  local target
  local -a valid_targets=()
  for target in "${FOLDER_ARGS[@]}"; do
    if [[ -d "$target" ]]; then
      valid_targets+=("$target")
    else
      echo "Warning: '$target' is not a directory or doesn't exist — skipping." >&2
    fi
  done

  if [[ ${#valid_targets[@]} -eq 0 ]]; then
    echo "Error: no valid target folders to scan." >&2
    exit 1
  fi

  [[ "$SHOW_GIT_INFO" -eq 1 ]] && print_git_info

  if [[ -n "$SEARCH_TEXT" ]]; then
    local mode="contains"
    [[ "$EXACT_MATCH" -eq 1 ]] && mode="exact"
    echo "Search: \"$SEARCH_TEXT\" (match: $mode, type: $SEARCH_TYPE)"
    echo ""
  fi

  for target in "${valid_targets[@]}"; do
    echo "--- $target ---"
    list_one_target "$target"
    echo ""
  done

  if [[ "$SHOW_EMPTY" -eq 1 ]]; then
    echo "--- EMPTY FOLDERS ---"
    for target in "${valid_targets[@]}"; do
      list_empty_dirs_for_target "$target"
    done
  fi
}

main
