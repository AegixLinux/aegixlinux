#!/usr/bin/env bash
# aegix-src-sync shared library.
# Source from other scripts via: source "$(dirname "$0")/src-sync-lib.sh"

# Default log file. Callers may override SRC_SYNC_LOG before sourcing or before calling log_line.
: "${SRC_SYNC_LOG:=$HOME/.local/state/aegix-src-sync.log}"

# expand_tilde: echo the given path with a leading ~ replaced by $HOME.
expand_tilde() {
  local p="$1"
  if [[ "$p" == "~" || "$p" == "~/"* ]]; then
    printf '%s%s\n' "$HOME" "${p:1}"
  else
    printf '%s\n' "$p"
  fi
}

# parse_conf: read a conf file and print one "live_path  aegix_path" line per tracked repo.
# Comments (# ...) and blank lines are ignored. Tilde expansion applied.
# Usage: parse_conf <conf_path>
parse_conf() {
  local conf="$1"
  if [[ ! -r "$conf" ]]; then
    echo "parse_conf: cannot read $conf" >&2
    return 1
  fi
  local line live aegix
  while IFS= read -r line; do
    line="${line%%#*}"                 # strip inline comments
    line="${line#"${line%%[![:space:]]*}"}"   # ltrim
    line="${line%"${line##*[![:space:]]}"}"   # rtrim
    [[ -z "$line" ]] && continue
    read -r live aegix <<<"$line"
    [[ -z "$live" || -z "$aegix" ]] && continue
    printf '%s  %s\n' "$(expand_tilde "$live")" "$(expand_tilde "$aegix")"
  done < "$conf"
}

# find_aegix_path: given a conf and a live src path, print the matching aegix path.
# Exits non-zero if not found.
# Usage: find_aegix_path <conf_path> <live_path>
#
# Reads the stream to EOF rather than returning from inside the loop. Returning
# early closes the process substitution while parse_conf is still writing the
# remaining entries, and parse_conf then takes EPIPE on every one of them. Under
# a default SIGPIPE disposition it just dies quietly, but git runs hooks with
# SIGPIPE ignored, so the write fails outright and bash reports
# "printf: write error: Broken pipe" once per conf entry after the match --
# which is why the noise scaled with the matched repo's position in the conf.
find_aegix_path() {
  local conf="$1" needle="$2" live aegix found=""
  needle="$(expand_tilde "$needle")"
  while read -r live aegix; do
    if [[ -z "$found" && "$live" == "$needle" ]]; then
      found="$aegix"
    fi
  done < <(parse_conf "$conf")
  [[ -n "$found" ]] || return 1
  printf '%s\n' "$found"
}

# log_line: append one structured line to $SRC_SYNC_LOG.
# Args: <repo> <status> <detail>
log_line() {
  local repo="$1" status="$2" detail="$3"
  local dir
  dir="$(dirname "$SRC_SYNC_LOG")"
  mkdir -p "$dir"
  printf '%s  %-7s %-5s %s\n' "$(date -u +%FT%TZ)" "$repo" "$status" "$detail" >> "$SRC_SYNC_LOG"
}

# sync_repo: the core sync operation (local-only — no network).
# Fetches live's current branch from live's local .git directory into the AEGIX
# submodule, resets the submodule to that commit, then stages the pointer bump
# in the AEGIX parent repo.
#
# Args: <live_path> <aegix_submodule_path> <aegix_parent_path>
# Returns: 0 on success; non-zero on fetch/reset/add failure (AEGIX untouched).
sync_repo() {
  local live="$1" aegix="$2" parent="$3"
  local repo_name
  repo_name="$(basename "$live")"

  # Determine branch in live
  local branch
  branch="$(git -C "$live" rev-parse --abbrev-ref HEAD)"

  local old_aegix_sha new_live_sha
  old_aegix_sha="$(git -C "$aegix" rev-parse --short HEAD 2>/dev/null || echo unknown)"
  new_live_sha="$(git -C "$live" rev-parse --short HEAD)"

  # Step 1: fetch the branch from live's local .git into AEGIX submodule
  if ! git -C "$aegix" fetch "$live" "$branch" 2>&1; then
    log_line "$repo_name" "WARN" "local fetch from live failed; AEGIX untouched"
    printf '[aegix-src-sync] %s: local fetch from live failed; AEGIX untouched\n' "$repo_name" >&2
    return 1
  fi

  # Step 2: reset --hard to FETCH_HEAD (the tip we just pulled from live)
  if ! git -C "$aegix" reset --hard FETCH_HEAD >/dev/null 2>&1; then
    log_line "$repo_name" "WARN" "reset in aegix failed"
    printf '[aegix-src-sync] %s: reset in AEGIX failed\n' "$repo_name" >&2
    return 1
  fi

  # Step 3: stage the submodule pointer bump in the AEGIX parent
  if ! git -C "$parent" add "$repo_name" 2>&1; then
    log_line "$repo_name" "WARN" "git add in aegix parent failed"
    printf '[aegix-src-sync] %s: git add in AEGIX parent failed\n' "$repo_name" >&2
    return 1
  fi

  log_line "$repo_name" "OK" "${old_aegix_sha}..${new_live_sha} staged"
  printf '[aegix-src-sync] %s: %s → %s, pointer staged in AEGIX parent\n' \
    "$repo_name" "$old_aegix_sha" "$new_live_sha"
  return 0
}

# backup_aegix_wip: if the AEGIX submodule has uncommitted changes, save them
# to a timestamped patch file and echo the path. If clean, echo nothing.
# Args: <aegix_submodule_path>
backup_aegix_wip() {
  local aegix="$1" repo_name
  repo_name="$(basename "$aegix")"
  if [[ -z "$(git -C "$aegix" status --porcelain)" ]]; then
    return 0
  fi
  local backup_dir="${SRC_SYNC_BACKUP_DIR:-$HOME/code/PROJECTS/AEGIX/tools/backups}"
  mkdir -p "$backup_dir"
  local ts
  ts="$(date -u +%Y%m%dT%H%M%SZ)"
  local patch="$backup_dir/${repo_name}-aegix-wip-${ts}.patch"
  git -C "$aegix" diff HEAD > "$patch"
  printf '%s\n' "$patch"
}
