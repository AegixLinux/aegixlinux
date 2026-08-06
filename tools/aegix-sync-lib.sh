#!/usr/bin/env bash
set -euo pipefail
# aegix-sync shared library. Source from tools/aegix-sync or the test harness.
# All paths parameterized via AEGIX_SYNC_* env (see plan Global Constraints).

: "${AEGIX_SYNC_HOME:=$HOME}"
: "${AEGIX_SYNC_REPO:=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
: "${AEGIX_SYNC_PROFILE:=$AEGIX_SYNC_REPO/iso-profile}"
: "${AEGIX_SYNC_DIR:=$AEGIX_SYNC_REPO/sync}"
: "${AEGIX_SYNC_PKGLIST_CMD:=pacman -Qqe}"
: "${AEGIX_SYNC_SKEL:=$AEGIX_SYNC_PROFILE/live-overlay/etc/skel}"

# fm_load <file>: load files.manifest into FM_PATTERNS ("decision<TAB>pattern" lines).
# Exits 1 on unknown decision or the same pattern appearing with two decisions.
fm_load() {
  local file="$1" line decision pattern
  FM_PATTERNS=()
  declare -gA _FM_SEEN=()
  while IFS= read -r line; do
    line="${line%%#*}"
    [[ -z "${line//[[:space:]]/}" ]] && continue
    IFS=$'\t' read -r decision pattern <<<"$line"
    case "$decision" in ship|never|iso|watch) ;; *)
      echo "files.manifest: unknown decision '$decision' for '$pattern'" >&2; return 1 ;;
    esac
    if [[ -n "${_FM_SEEN[$pattern]:-}" && "${_FM_SEEN[$pattern]}" != "$decision" ]]; then
      echo "files.manifest: '$pattern' is both ${_FM_SEEN[$pattern]} and $decision" >&2; return 1
    fi
    _FM_SEEN["$pattern"]="$decision"
    FM_PATTERNS+=("$decision"$'\t'"$pattern")
  done < "$file"
}

# fm_lookup <relpath>: print winning decision for a $HOME-relative path, or "undecided".
# Longest matching pattern wins. "watch" entries never decide a file.
fm_lookup() {
  local path="$1" best="" bestlen=-1 entry decision pattern
  for entry in "${FM_PATTERNS[@]}"; do
    decision="${entry%%$'\t'*}" pattern="${entry#*$'\t'}"
    [[ "$decision" == "watch" ]] && continue
    local hit=0
    if [[ "$path" == "$pattern" ]]; then hit=1
    elif [[ "$pattern" == */ && ( "$path" == "$pattern"* ) ]]; then hit=1
    elif [[ "$path" == $pattern ]]; then hit=1   # bash glob
    fi
    if [[ "$hit" -eq 1 && "${#pattern}" -gt "$bestlen" ]]; then
      best="$decision" bestlen="${#pattern}"
    fi
  done
  printf '%s\n' "${best:-undecided}"
}

# pm_load <file>: load packages.manifest. See plan Task 2 for format.
pm_load() {
  local file="$1" line tags name f3 f4
  PM_ORDER=(); declare -gA PM_TAGS=() PM_DESC=() PM_URL=()
  while IFS= read -r line; do
    line="${line%%#*}"; [[ -z "${line//[[:space:]]/}" ]] && continue
    IFS=$'\t' read -r tags name f3 f4 <<<"$line"
    if [[ ",$tags," == *,never,* && "$tags" != "never" ]]; then
      echo "packages.manifest: 'never' must be sole tag for '$name'" >&2; return 1
    fi
    local t
    for t in ${tags//,/ }; do
      case "$t" in rootfs|rootfs-init|livefs|livefs-init|barbs|aur|git|never) ;; *)
        echo "packages.manifest: unknown tag '$t' for '$name'" >&2; return 1 ;;
      esac
    done
    if [[ ",$tags," == *,git,* ]]; then PM_URL["$name"]="$f3"; PM_DESC["$name"]="${f4//\"/}"
    else PM_DESC["$name"]="${f3//\"/}"; fi
    PM_TAGS["$name"]="$tags"; PM_ORDER+=("$name")
  done < "$file"
}

# pm_new_packages <installed-file>: installed names with no manifest entry.
pm_new_packages() {
  local p
  while IFS= read -r p; do
    [[ -z "${PM_TAGS[$p]:-}" ]] && printf '%s\n' "$p"
  done < "$1"
  return 0
}

# pm_gone_packages <installed-file>: manifest names expected live but not installed.
# ISO-only tag sets (livefs*, rootfs-init only) and never are skipped.
pm_gone_packages() {
  local installed="$1" name
  declare -A have=()
  while IFS= read -r name; do have["$name"]=1; done < "$installed"
  for name in "${PM_ORDER[@]}"; do
    local tags=",${PM_TAGS[$name]},"
    [[ "$tags" == ",never," ]] && continue
    # expected-on-live iff it has a tag implying live presence
    if [[ "$tags" == *,rootfs,* || "$tags" == *,barbs,* || "$tags" == *,aur,* || "$tags" == *,git,* ]]; then
      [[ -z "${have[$name]:-}" ]] && printf '%s\n' "$name"
    fi
  done
  return 0
}

# rules_load <file>: load sanitize.rules into RULES[] with placeholders expanded.
rules_load() {
  local file="$1" line
  : "${LIVE_USER:=$(id -un)}"
  : "${LIVE_HOME:=$AEGIX_SYNC_HOME}"
  : "${LIVE_EMAIL:=$(git config user.email 2>/dev/null || echo NO-EMAIL-SET)}"
  RULES=()
  while IFS= read -r line; do
    [[ "$line" =~ ^[[:space:]]*# ]] && continue              # skip full-line comments
    [[ -z "${line//[[:space:]]/}" ]] && continue             # skip blank lines
    line="${line//\$\{LIVE_USER\}/$LIVE_USER}"
    line="${line//\$\{LIVE_HOME\}/$LIVE_HOME}"
    line="${line//\$\{LIVE_EMAIL\}/$LIVE_EMAIL}"
    case "${line%%$'\t'*}" in sub|strip-line|strip-block|forbid|allow) ;; *)
      echo "sanitize.rules: unknown rule type in: $line" >&2; return 1 ;;
    esac
    RULES+=("$line")
  done < "$file"
}

# sanitize_tree <root>: apply sub/strip rules to every text file under root.
sanitize_tree() {
  local root="$1" f rel rule type a b c
  while IFS= read -r -d '' f; do
    grep -Iq . "$f" 2>/dev/null || continue        # skip binary/empty
    rel="${f#"$AEGIX_SYNC_PROFILE"/}"
    local script=""
    for rule in "${RULES[@]+"${RULES[@]}"}"; do
      IFS=$'\t' read -r type a b c <<<"$rule"
      case "$type" in
        sub)        [[ -z "$c" || "$rel" == $c ]] && script+="s"$'\x01'"$a"$'\x01'"$b"$'\x01'"g;" ;;
        strip-line) [[ -z "$b" || "$rel" == $b ]] && script+="\\"$'\x01'"$a"$'\x01'"d;" ;;
        strip-block) script+="\\"$'\x01'"$a"$'\x01'",\\"$'\x01'"$b"$'\x01'"d;" ;;
      esac
    done
    [[ -n "$script" ]] && sed -E -i "$script" "$f"
  done < <(find "$root" -type f -print0)
  return 0
}

# verify_tree <root>: forbid/allow scan. Returns 1 if any un-allowed hit. No bypass.
# Match-scoped allow: for each forbid match, only suppress if ALL matched substrings
# match an allow regex. This prevents an allow for one pattern from blinding another.
#
# Text and binary content are scanned by two entirely separate paths. Binary
# file bytes are NEVER piped through a bash variable/here-string: bash's
# `read` (and `$()`) silently truncate/mangle content once a long run of NUL
# bytes is involved — verified against a real compiled ELF with a secret
# string sitting past a multi-hundred-byte NUL run: grep itself reports the
# full ~4KB matching line, but `read -r` into a variable captured only the
# first ~64 bytes, so the substring-extraction step downstream saw nothing
# and the match-scoped allow logic vacuously passed it. Compiled binaries are
# exactly the NUL-run-heavy class this gate exists to catch, so for them we
# run grep directly against the file (content never leaves the grep process)
# and treat any forbid hit as an unconditional failure — allow rules exist to
# excuse text placeholders (e.g. a documented example IP); there is no
# legitimate allowlisted secret inside a binary.
verify_tree() {
  local root="$1" rule type pat msg bad=0 hit line f
  [[ -d "$root" ]] || { echo "verify_tree: root not found: $root" >&2; return 1; }

  local allows=()
  for rule in "${RULES[@]}"; do
    IFS=$'\t' read -r type pat msg <<<"$rule"
    [[ "$type" == "allow" ]] && allows+=("$pat")
  done

  # Text files: recursive scan skips binaries (-I) — those are handled
  # below. Match-scoped allow narrowing unchanged.
  for rule in "${RULES[@]}"; do
    IFS=$'\t' read -r type pat msg <<<"$rule"
    [[ "$type" == "forbid" ]] || continue
    while IFS= read -r hit; do
      line="${hit#*:*:}"

      # Extract all matched substrings for this forbid pattern
      local matched_strs=()
      while IFS= read -r ms; do
        [[ -n "$ms" ]] && matched_strs+=("$ms")
      done < <(grep -oE "$pat" <<<"$line")

      # Only suppress if ALL matched substrings match an allow regex
      local all_allowed=1
      for ms in "${matched_strs[@]+"${matched_strs[@]}"}"; do
        local ms_ok=0
        for a in "${allows[@]}"; do
          [[ "$ms" =~ $a ]] && { ms_ok=1; break; }
        done
        if [[ "$ms_ok" -eq 0 ]]; then
          all_allowed=0
          break
        fi
      done

      if [[ "$all_allowed" -eq 1 ]]; then
        continue
      fi

      printf 'VERIFY FAIL %s  [%s]\n' "$hit" "${msg:-$pat}" >&2
      bad=1
    done < <(grep -rnIE "$pat" "$root" 2>/dev/null || true)
  done

  # Binary files: unconditional fail on any forbid hit, checked directly
  # against the file (-a: force binary content to be treated as text for
  # matching purposes; -q: boolean, no content transits bash at all).
  while IFS= read -r -d '' f; do
    grep -Iq . "$f" 2>/dev/null && continue   # text: handled above
    for rule in "${RULES[@]}"; do
      IFS=$'\t' read -r type pat msg <<<"$rule"
      [[ "$type" == "forbid" ]] || continue
      if grep -aqE "$pat" "$f" 2>/dev/null; then
        printf 'VERIFY FAIL %s: binary content matches  [%s]\n' "$f" "${msg:-$pat}" >&2
        bad=1
      fi
    done
  done < <(find "$root" -type f -print0 2>/dev/null)

  # Scan symlink targets for forbidden content
  for rule in "${RULES[@]}"; do
    IFS=$'\t' read -r type pat msg <<<"$rule"
    [[ "$type" == "forbid" ]] || continue
    while IFS= read -r -d '' symlink; do
      local target; target="$(readlink "$symlink")"

      # Extract all matched substrings from symlink target
      local matched_strs=()
      while IFS= read -r ms; do
        [[ -n "$ms" ]] && matched_strs+=("$ms")
      done < <(grep -oE "$pat" <<<"$target" || true)

      # Only suppress if ALL matched substrings match an allow regex
      local all_allowed=1
      for ms in "${matched_strs[@]+"${matched_strs[@]}"}"; do
        local ms_ok=0
        for a in "${allows[@]}"; do
          [[ "$ms" =~ $a ]] && { ms_ok=1; break; }
        done
        if [[ "$ms_ok" -eq 0 ]]; then
          all_allowed=0
          break
        fi
      done

      if [[ "$all_allowed" -eq 1 ]]; then
        continue
      fi

      printf 'VERIFY FAIL %s -> %s  [%s]\n' "$symlink" "$target" "${msg:-$pat}" >&2
      bad=1
    done < <(find "$root" -type l -print0 2>/dev/null || true)
  done
  return "$bad"
}

# _pm_yaml_lines <tag>: print "    - name" for manifest pkgs having <tag>, manifest order.
_pm_yaml_lines() {
  local tag="$1" name
  for name in "${PM_ORDER[@]}"; do
    [[ ",${PM_TAGS[$name]}," == *,"$tag",* ]] && printf '    - %s\n' "$name"
  done
  return 0
}

# gen_profile_yaml <tmpl> <out>: abort if any marker remains (whitespace-wrapped or other).
gen_profile_yaml() {
  local tmpl="$1" out="$2" line
  : > "$out"
  while IFS= read -r line; do
    case "$line" in
      '@ROOTFS_PACKAGES@')   _pm_yaml_lines rootfs      >> "$out" ;;
      '@ROOTFS_INIT_RUNIT@') _pm_yaml_lines rootfs-init >> "$out" ;;
      '@LIVEFS_PACKAGES@')   _pm_yaml_lines livefs      >> "$out" ;;
      '@LIVEFS_INIT_RUNIT@') _pm_yaml_lines livefs-init >> "$out" ;;
      *) printf '%s\n' "$line" >> "$out" ;;
    esac
  done < "$tmpl"
  # Validate: no markers remain (catches whitespace-wrapped @MARKERS@, etc.)
  if grep -q '@[A-Z_]\+@' "$out"; then
    grep -n '@[A-Z_]\+@' "$out" | sed 's/^/  /' >&2
    printf 'gen_profile_yaml: unconsumed marker(s) in %s\n' "$out" >&2
    return 1
  fi
}

# gen_barbs_csv <out>: barbs/aur/git rows in manifest order.
gen_barbs_csv() {
  local out="$1" name tags
  mkdir -p "$(dirname "$out")"
  : > "$out"
  for name in "${PM_ORDER[@]}"; do
    tags=",${PM_TAGS[$name]},"
    if   [[ "$tags" == *,git,* ]]; then printf 'G,%s,"%s"\n' "${PM_URL[$name]}" "${PM_DESC[$name]}" >> "$out"
    elif [[ "$tags" == *,aur,* ]]; then printf 'A,%s,"%s"\n' "$name" "${PM_DESC[$name]}" >> "$out"
    elif [[ "$tags" == *,barbs,* ]]; then printf ',%s,"%s"\n' "$name" "${PM_DESC[$name]}" >> "$out"
    fi
  done
}

# discover_undecided: print undecided paths under watch dirs; new dirs collapse to "DIR p/".
discover_undecided() {
  local entry decision pattern d f rel top
  for entry in "${FM_PATTERNS[@]}"; do
    decision="${entry%%$'\t'*}" pattern="${entry#*$'\t'}"
    [[ "$decision" == "watch" ]] || continue
    d="$AEGIX_SYNC_HOME/$pattern"
    [[ -d "$d" ]] || continue
    # direct children first: whole new dirs collapse.
    # find (not a glob) so leading-dot entries aren't silently invisible.
    while IFS= read -r -d '' top; do
      rel="${top#"$AEGIX_SYNC_HOME"/}"
      if [[ -d "$top" ]]; then
        if [[ "$(fm_lookup "$rel/")" == "undecided" ]]; then
          # any manifest pattern deeper inside? then descend instead of collapsing
          if _fm_deeper_pattern "$rel"; then
            while IFS= read -r -d '' f; do
              rel="${f#"$AEGIX_SYNC_HOME"/}"
              [[ "$(fm_lookup "$rel")" == "undecided" ]] && printf '%s\n' "$rel"
            done < <(find "$top" ! -type d -print0)
          else
            printf 'DIR %s/\n' "$rel"
          fi
        fi
      else
        [[ "$(fm_lookup "$rel")" == "undecided" ]] && printf '%s\n' "$rel"
      fi
    done < <(find "$d" -mindepth 1 -maxdepth 1 -print0)
  done
  return 0
}

# _fm_deeper_pattern <reldir>: true if any manifest pattern lies strictly under reldir.
_fm_deeper_pattern() {
  local rel="$1" entry pattern
  for entry in "${FM_PATTERNS[@]}"; do
    pattern="${entry#*$'\t'}"
    [[ "$pattern" == "$rel"/?* ]] && return 0
  done
  return 1
}

# triage_run <answers-file|--> [installed-pkgs-file]: resolve undecided files (and,
# if an installed-pkgs-file is given and a packages.manifest is loaded, undecided
# packages) against the answers file; append decisions to the manifests.
# Answers file lines: "decision<TAB>pattern" (pattern may be an exact path, a glob,
# or a dir ending in "/"); first match wins. "--" prompts interactively on /dev/tty.
triage_run() {
  local answers="$1" installed="${2:-}" item
  local -A _TRIAGE_APPENDED_FILES=()
  local _TRIAGE_STAMPED=0

  while IFS= read -r item; do
    [[ -z "$item" ]] && continue
    _triage_handle_item "$item" "$answers"
  done < <(discover_undecided)

  if [[ -n "$installed" && -n "${PM_ORDER+x}" ]]; then
    local -A _TRIAGE_APPENDED_PKGS=()
    local _TRIAGE_PKG_STAMPED=0
    local name result pdecision ppattern
    while IFS= read -r name; do
      [[ -z "$name" ]] && continue
      result="$(_pm_triage_decide "$answers" "$name")"
      pdecision="${result%%$'\t'*}" ppattern="${result#*$'\t'}"
      case "$pdecision" in
        never|barbs|aur)
          if [[ -z "${_TRIAGE_APPENDED_PKGS[$ppattern]:-}" ]]; then
            if [[ "$_TRIAGE_PKG_STAMPED" -eq 0 ]]; then
              printf '# triage %s\n' "$(date +%F)" >> "$AEGIX_SYNC_DIR/packages.manifest"
              _TRIAGE_PKG_STAMPED=1
            fi
            case "$pdecision" in
              never) printf 'never\t%s\n' "$ppattern" ;;
              barbs) printf 'barbs\t%s\t""\n' "$ppattern" ;;
              aur)   printf 'aur\t%s\t""\n' "$ppattern" ;;
            esac >> "$AEGIX_SYNC_DIR/packages.manifest"
            _TRIAGE_APPENDED_PKGS["$ppattern"]=1
          fi ;;
        *) : ;;   # later
      esac
    done < <(pm_new_packages "$installed")
    [[ -f "$AEGIX_SYNC_DIR/packages.manifest" ]] && pm_load "$AEGIX_SYNC_DIR/packages.manifest"
  fi

  fm_load "$AEGIX_SYNC_DIR/files.manifest"
}

# _triage_handle_item <item> <answers>: process one discover_undecided line
# ("DIR path/" or a plain file path). Relies on caller's (triage_run's) locals
# _TRIAGE_APPENDED_FILES / _TRIAGE_STAMPED, visible via bash dynamic scoping.
_triage_handle_item() {
  local item="$1" answers="$2" is_dir=0 path result decision pattern
  if [[ "$item" == "DIR "* ]]; then is_dir=1; path="${item#DIR }"; else path="$item"; fi

  result="$(_triage_decide "$answers" "$path" "$is_dir")"
  decision="${result%%$'\t'*}" pattern="${result#*$'\t'}"
  case "$decision" in
    ship|never)
      if [[ -z "${_TRIAGE_APPENDED_FILES[$pattern]:-}" ]]; then
        if [[ "$_TRIAGE_STAMPED" -eq 0 ]]; then
          printf '# triage %s\n' "$(date +%F)" >> "$AEGIX_SYNC_DIR/files.manifest"
          _TRIAGE_STAMPED=1
        fi
        printf '%s\t%s\n' "$decision" "$pattern" >> "$AEGIX_SYNC_DIR/files.manifest"
        _TRIAGE_APPENDED_FILES["$pattern"]=1
      fi ;;
    descend)
      [[ "$is_dir" -eq 1 ]] || return 0
      local f rel
      while IFS= read -r -d '' f; do
        rel="${f#"$AEGIX_SYNC_HOME"/}"
        [[ "$(fm_lookup "$rel")" == "undecided" ]] && _triage_handle_item "$rel" "$answers"
      done < <(find "$AEGIX_SYNC_HOME/${path%/}" ! -type d -print0)
      ;;
    *) : ;;   # later: left undecided, re-asked next run
  esac
}

# _triage_decide <answers|--> <path> <is_dir>: print "decision<TAB>matched-pattern".
# Non-interactive: pattern is the answers-file line that matched (exact/glob/dir).
# Interactive: pattern is the path itself (files) or the dir path (dirs).
_triage_decide() {
  local answers="$1" path="$2" is_dir="${3:-0}" a d p
  if [[ "$answers" != "--" ]]; then
    while IFS=$'\t' read -r d p; do
      [[ -z "$d" ]] && continue
      # Exact/glob match always applies. The dir-prefix match (a "ship .foo/" or
      # "never .foo/" line answering every path under .foo/) does NOT apply to a
      # "descend" line: descend only targets the DIR item itself (whose own path
      # already ends in "/" and is caught by the exact-match arm above), never a
      # cascading match against its individual children — otherwise a leading
      # "descend .foo/" line would shadow more specific ship/never lines below it.
      if [[ "$path" == "$p" || "$path" == $p \
            || ( "$d" != "descend" && "$p" == */ && "$path" == "$p"* ) ]]; then
        printf '%s\t%s\n' "$d" "$p"; return
      fi
    done < "$answers"
    printf 'later\t\n'
    return
  fi
  if [[ "$is_dir" -eq 1 ]]; then
    read -r -p "NEW DIR: $path  [s]hip [n]ever [d]escend [l]ater > " a < /dev/tty
  else
    read -r -p "NEW: $path  [s]hip [n]ever [l]ater > " a < /dev/tty
  fi
  case "$a" in
    s) printf 'ship\t%s\n' "$path" ;;
    n) printf 'never\t%s\n' "$path" ;;
    d) if [[ "$is_dir" -eq 1 ]]; then printf 'descend\t%s\n' "$path"; else printf 'later\t\n'; fi ;;
    *) printf 'later\t\n' ;;
  esac
}

# _pm_triage_decide <answers|--> <name>: print "decision<TAB>matched-pattern" for a
# package name (never|barbs|aur|later). Interactive mode suggests aur when the name
# is already foreign-installed (pacman -Qqm), else barbs.
_pm_triage_decide() {
  local answers="$1" name="$2" a d p
  if [[ "$answers" != "--" ]]; then
    while IFS=$'\t' read -r d p; do
      [[ -z "$d" ]] && continue
      if [[ "$name" == "$p" || "$name" == $p ]]; then
        printf '%s\t%s\n' "$d" "$p"; return
      fi
    done < "$answers"
    printf 'later\t\n'
    return
  fi
  local suggestion="barbs"
  pacman -Qqm 2>/dev/null | grep -qx "$name" && suggestion="aur"
  read -r -p "NEW PKG: $name  [b]arbs [a]ur [n]ever [l]ater (suggest: $suggestion) > " a < /dev/tty
  case "$a" in
    b) printf 'barbs\t%s\n' "$name" ;;
    a) printf 'aur\t%s\n' "$name" ;;
    n) printf 'never\t%s\n' "$name" ;;
    *) printf 'later\t\n' ;;
  esac
}

# _skel_rel_in_repo: print AEGIX_SYNC_SKEL's path relative to AEGIX_SYNC_REPO,
# suitable for git pathspecs/index paths against that repo. Falls back to
# $AEGIX_SYNC_SKEL_REL when SKEL isn't actually a child of REPO — the case
# when drift_status replays capture_run against a /tmp scratch copy but still
# needs iso content out of the *real* repo's index. Returns 1 (prints nothing)
# if neither resolves; callers must then skip iso-restore rather than mangle
# a path.
_skel_rel_in_repo() {
  if [[ "$AEGIX_SYNC_SKEL" == "$AEGIX_SYNC_REPO"/* ]]; then
    printf '%s\n' "${AEGIX_SYNC_SKEL#"$AEGIX_SYNC_REPO"/}"
    return 0
  fi
  if [[ -n "${AEGIX_SYNC_SKEL_REL:-}" ]]; then
    printf '%s\n' "$AEGIX_SYNC_SKEL_REL"
    return 0
  fi
  return 1
}

# _iso_restore_file <repo-relative-path> <dest-file>: materialize one
# git-tracked iso file from the repo's index into <dest-file>, wherever that
# file actually lives (real skel, or a drift_status scratch copy elsewhere).
# Unlike `git checkout`, this never writes into the repo's own working tree —
# the destination is entirely controlled by the caller. Fails (nonzero, dest
# left untouched by design of the caller's fallback) if the repo has no such
# tracked content, preserving "iso comes only from git, never from live".
_iso_restore_file() {
  local repo_rel="$1" dest="$2"
  mkdir -p "$(dirname "$dest")"
  git -C "$AEGIX_SYNC_REPO" show ":$repo_rel" > "$dest" 2>/dev/null
}

# capture_run: pull every "ship" path live -> skel. Live wins; deletions propagate.
capture_run() {
  local entry decision pattern
  local skel_rel; skel_rel="$(_skel_rel_in_repo)" || skel_rel=""
  for entry in "${FM_PATTERNS[@]}"; do
    decision="${entry%%$'\t'*}" pattern="${entry#*$'\t'}"
    [[ "$decision" == "ship" ]] || continue
    local src="$AEGIX_SYNC_HOME/$pattern" dst="$AEGIX_SYNC_SKEL/$pattern"
    if [[ "$pattern" == */ ]]; then
      mkdir -p "$dst"
      rsync -a --delete --exclude .git --exclude .gitignore --exclude '*.o' --exclude '*.orig' "$src" "$dst"
      # suckless built binary: .local/src/<tool>/ -> remove skel copy of <tool>
      if [[ "$pattern" == .local/src/*/ ]]; then
        local tool; tool="$(basename "$pattern")"
        rm -f "$dst$tool"
        # A captured .gitignore is invisible to the ship channel above (we
        # exclude the file itself but not what it hides): anything the live
        # repo ignores — build artifacts, local state — would otherwise ship
        # unless the live repo itself marks it ignored. Purge those paths
        # from the skel copy so a tool's .gitignore stays authoritative.
        if git -C "$src" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
          local ig
          while IFS= read -r ig; do
            [[ -z "$ig" ]] && continue
            rm -rf "$dst${ig%/}" || true
          done < <(git -C "$src" ls-files -oi --exclude-standard 2>/dev/null || true)
        fi
      fi
      # restore iso-marked paths from git (may have been deleted by rsync).
      # Enumerate git's own tracked list under each iso pattern and write
      # each one into $AEGIX_SYNC_SKEL directly — not `git checkout`, which
      # always writes into the repo's working tree and would silently no-op
      # (or worse, touch the real skel) when SKEL points at a scratch copy.
      if [[ -n "$skel_rel" ]]; then
        local entry2 decision2 pattern2
        for entry2 in "${FM_PATTERNS[@]}"; do
          decision2="${entry2%%$'\t'*}" pattern2="${entry2#*$'\t'}"
          [[ "$decision2" == "iso" ]] || continue
          # if iso path is inside this directory, restore from git
          [[ "$pattern2" == "$pattern"* ]] || continue
          local gf rel2
          while IFS= read -r gf; do
            rel2="${gf#"$skel_rel"/}"
            _iso_restore_file "$gf" "$AEGIX_SYNC_SKEL/$rel2" || true
          done < <(git -C "$AEGIX_SYNC_REPO" ls-files -- "$skel_rel/$pattern2" 2>/dev/null)
        done
      fi
      # reconcile anything inside that a longer pattern says never/iso (files AND symlinks)
      # iso paths: pre-restore loop pulled from git; this fallback deletes if git has no copy
      local f rel
      while IFS= read -r -d '' f; do
        rel="${f#"$AEGIX_SYNC_SKEL"/}"
        case "$(fm_lookup "$rel")" in
          ship) ;;
          iso)  if [[ -n "$skel_rel" ]] && _iso_restore_file "$skel_rel/$rel" "$f"; then :
                else rm -f "$f"; fi ;;
          *)    rm -f "$f" ;;
        esac
      done < <(find "$dst" ! -type d -print0)
      find "$dst" -type d -empty -delete
    elif [[ "$pattern" == *[\*\?\[]* ]]; then
      local m
      while IFS= read -r m; do
        rel="${m#"$AEGIX_SYNC_HOME"/}"
        install -D -m "$(stat -c %a "$m")" "$m" "$AEGIX_SYNC_SKEL/$rel"
      done < <(compgen -G "$AEGIX_SYNC_HOME/$pattern" || true)
    else
      if [[ -L "$src" ]]; then
        # symlink source: preserve link-ness with cp -P
        mkdir -p "$(dirname "$dst")"
        cp -P --remove-destination "$src" "$dst"
      elif [[ -e "$src" ]]; then
        install -D -m "$(stat -c %a "$src")" "$src" "$dst"
      elif [[ -e "$dst" ]]; then
        rm -f "$dst"; printf 'deleted: %s\n' "$pattern"
      fi
    fi
  done
}

# _drift_status_na <reason>: emit the "unknown" drift report to stdout (and
# <reason> to stderr) when drift_status can't safely run against the real
# profile. Never a lie of "0 drift" — an unresolvable "?" instead.
_drift_status_na() {
  printf 'drift_status: %s\n' "$1" >&2
  printf '? files drifted, ? undecided, ? new packages, ? gone packages\n'
}

# drift_status: read-only drift report (never mutates the repo or manifests).
# Copies AEGIX_SYNC_PROFILE to a scratch dir, replays capture_run + sanitize_tree
# against the scratch copy with AEGIX_SYNC_PROFILE/AEGIX_SYNC_SKEL repointed only
# inside a subshell (so the real values are untouched once it exits), diffs the
# scratch tree against the real profile tree, and reports package drift against
# $AEGIX_SYNC_PKGLIST_CMD. FM_PATTERNS/RULES/PM_* are read-only here — never
# reloaded — so this can't desync the manifest state already loaded by the
# caller. Always exits 0: this is a report, not a gate.
drift_status() {
  local scratch inst
  scratch="$(mktemp -d /tmp/aegix-sync-status.XXXXXX)"
  inst="$(mktemp /tmp/aegix-sync-status-pkgs.XXXXXX)"
  trap 'rm -rf "$scratch"; rm -f "$inst"' RETURN

  if [[ ! -d "$AEGIX_SYNC_PROFILE" ]]; then
    _drift_status_na "profile not found: $AEGIX_SYNC_PROFILE"
    return 0
  fi
  cp -a "$AEGIX_SYNC_PROFILE/." "$scratch/" || {
    _drift_status_na "failed to copy profile: $AEGIX_SYNC_PROFILE"
    return 0
  }

  local n
  n="$(
    (
      # Derive the real SKEL's repo-relative path *before* repointing PROFILE/
      # SKEL at the scratch copy below, and export it — capture_run's iso
      # restore can't derive this itself once SKEL points outside the repo
      # (a /tmp scratch dir), so it falls back to this for the replay.
      skel_rel="${AEGIX_SYNC_SKEL#"$AEGIX_SYNC_REPO"/}"
      export AEGIX_SYNC_SKEL_REL="$skel_rel"
      export AEGIX_SYNC_PROFILE="$scratch" AEGIX_SYNC_SKEL="$scratch/live-overlay/etc/skel"
      capture_run >/dev/null
      sanitize_tree "$AEGIX_SYNC_PROFILE"
    ) || true
    diff -rq "$scratch" "$AEGIX_SYNC_PROFILE" 2>/dev/null | wc -l
  )" || true

  $AEGIX_SYNC_PKGLIST_CMD > "$inst" 2>/dev/null || true

  local u p g
  u="$(discover_undecided | wc -l)"
  p="$(pm_new_packages "$inst" | wc -l)"
  g="$(pm_gone_packages "$inst" | wc -l)"

  printf '%s files drifted, %s undecided, %s new packages, %s gone packages\n' \
    "$n" "$u" "$p" "$g"
}
