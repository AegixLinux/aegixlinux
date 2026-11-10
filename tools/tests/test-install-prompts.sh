#!/usr/bin/env bash
# Tests for the interactive prompt helpers in install.sh.
# The installer itself cannot be sourced (it starts partitioning), so this
# extracts just the block between the "prompt helpers" markers and drives the
# functions with stdin.
# Usage: ./test-install-prompts.sh   (exit 0 = all asserts pass)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL="$(dirname "$(dirname "$SCRIPT_DIR")")/iso-profile/live-overlay/root/install.sh"
TESTS_RUN=0 TESTS_FAILED=0
pass() { printf '  \033[32m✓\033[0m %s\n' "$*"; TESTS_RUN=$((TESTS_RUN+1)); }
fail() { printf '  \033[31m✗\033[0m %s\n' "$*"; TESTS_RUN=$((TESTS_RUN+1)); TESTS_FAILED=$((TESTS_FAILED+1)); }
assert_eq() { [[ "$1" == "$2" ]] && pass "$3" || fail "$3 (expected=[$1] actual=[$2])"; }
finish() {
    echo
    if [[ $TESTS_FAILED -eq 0 ]]; then
        printf '\033[32mAll %d asserts passed.\033[0m\n' "$TESTS_RUN"
    else
        printf '\033[31m%d of %d asserts failed.\033[0m\n' "$TESTS_FAILED" "$TESTS_RUN"; exit 1
    fi
}

helpers="$(awk '/^### >>> prompt helpers/,/^### <<< prompt helpers/' "$INSTALL")"
if [[ -z "$helpers" ]]; then
    fail "install.sh has a '### >>> prompt helpers' ... '### <<< prompt helpers' block"
    finish
fi
pass "install.sh has the prompt helpers block"

# run <stdin> <command...>: run a helper call with stdin, print the variable
# it set (named by the last word of the command's first arg), or FAILED.
run() {
    local input="$1"; shift
    printf '%b' "$input" | bash -c "set -euo pipefail; IFS=\$'\n\t'; $helpers
        $*
        printf '%s' \"\$OUT\"" 2>/dev/null || printf 'FAILED'
}

echo "prompt_password"
assert_eq "s3cret"     "$(run 's3cret\ns3cret\n'               "prompt_password OUT 'Password'")" "accepts a confirmed password"
assert_eq "s3cret"     "$(run '\n\ns3cret\ns3cret\n'           "prompt_password OUT 'Password'")" "re-prompts on empty, then accepts"
assert_eq "s3cret"     "$(run 's3cret\ntypo\ns3cret\ns3cret\n' "prompt_password OUT 'Password'")" "re-prompts on mismatch, then accepts"
assert_eq "two words!" "$(run 'two words!\ntwo words!\n'       "prompt_password OUT 'Password'")" "keeps spaces and punctuation"
assert_eq "FAILED"     "$(run '\n\n'                           "prompt_password OUT 'Password'")" "end of input does not loop forever"

echo "prompt_username"
assert_eq "timothy"   "$(run 'timothy\n'                       "prompt_username OUT aegix")" "accepts a valid name"
assert_eq "aegix"     "$(run '\n'                              "prompt_username OUT aegix")" "empty answer takes the default"
assert_eq "timothy"   "$(run 'Timothy\ntimothy\n'              "prompt_username OUT aegix")" "rejects uppercase, re-prompts"
assert_eq "tim_b-2"   "$(run '2tim\n-tim\ntim b\ntim_b-2\n'    "prompt_username OUT aegix")" "rejects leading digit/hyphen and spaces"
assert_eq "okname"    "$(run "$(printf 'a%.0s' {1..33})\nokname\n" "prompt_username OUT aegix")" "rejects names over 32 chars"
assert_eq "okname"    "$(run 'root\nbin\nokname\n'             "prompt_username OUT aegix")" "rejects root and existing system users"
assert_eq "okname"    "$(run 'wheel\nvideo\nokname\n'          "prompt_username OUT aegix")" "rejects names of groups the user joins"
assert_eq "FAILED"    "$(run 'BAD\n'                           "prompt_username OUT aegix")" "end of input does not loop forever"

echo "prompt_hostname"
assert_eq "thinkpad-p50" "$(run 'thinkpad-p50\n'               "prompt_hostname OUT aegix")" "accepts a valid hostname"
assert_eq "aegix"        "$(run '\n'                           "prompt_hostname OUT aegix")" "empty answer takes the default"
assert_eq "MyBox"        "$(run 'MyBox\n'                      "prompt_hostname OUT aegix")" "allows uppercase letters"
assert_eq "box1"         "$(run 'my box\nbox_1\n-box\nbox-\nbox.local\nbox1\n' "prompt_hostname OUT aegix")" "rejects spaces, underscores, edge hyphens, dots"
assert_eq "okhost"       "$(run "$(printf 'h%.0s' {1..64})\nokhost\n" "prompt_hostname OUT aegix")" "rejects labels over 63 chars"
assert_eq "FAILED"       "$(run 'bad host\n'                   "prompt_hostname OUT aegix")" "end of input does not loop forever"

finish
