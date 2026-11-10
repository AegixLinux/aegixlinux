#!/usr/bin/env bash
# Tests for the password prompt helper in install.sh.
# The installer itself cannot be sourced (it starts partitioning), so this
# extracts just the prompt_password function and drives it with stdin.
# Usage: ./test-install-prompts.sh   (exit 0 = all asserts pass)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL="$(dirname "$(dirname "$SCRIPT_DIR")")/iso-profile/live-overlay/root/install.sh"
TESTS_RUN=0 TESTS_FAILED=0
pass() { printf '  \033[32m✓\033[0m %s\n' "$*"; TESTS_RUN=$((TESTS_RUN+1)); }
fail() { printf '  \033[31m✗\033[0m %s\n' "$*"; TESTS_RUN=$((TESTS_RUN+1)); TESTS_FAILED=$((TESTS_FAILED+1)); }
assert_eq() { [[ "$1" == "$2" ]] && pass "$3" || fail "$3 (expected=[$1] actual=[$2])"; }

fn="$(awk '/^prompt_password\(\) \{/,/^\}/' "$INSTALL")"
if [[ -z "$fn" ]]; then
    fail "install.sh defines prompt_password()"
    printf '\033[31m%d of %d asserts failed.\033[0m\n' "$TESTS_FAILED" "$TESTS_RUN"; exit 1
fi
pass "install.sh defines prompt_password()"

# run_prompt <stdin>: print the value prompt_password stored, or FAILED.
run_prompt() {
    printf '%b' "$1" | bash -c "set -euo pipefail; IFS=\$'\n\t'; $fn
        prompt_password PW 'Password for test'
        printf '%s' \"\$PW\"" 2>/dev/null || printf 'FAILED'
}

assert_eq "s3cret"       "$(run_prompt 's3cret\ns3cret\n')"                  "accepts a confirmed password"
assert_eq "s3cret"       "$(run_prompt '\n\ns3cret\ns3cret\n')"              "re-prompts on empty, then accepts"
assert_eq "s3cret"       "$(run_prompt 's3cret\ntypo\ns3cret\ns3cret\n')"    "re-prompts on mismatch, then accepts"
assert_eq "two words!"   "$(run_prompt 'two words!\ntwo words!\n')"          "keeps spaces and punctuation"
assert_eq "FAILED"       "$(run_prompt '\n\n')"                              "end of input does not loop forever"

echo
if [[ $TESTS_FAILED -eq 0 ]]; then
    printf '\033[32mAll %d asserts passed.\033[0m\n' "$TESTS_RUN"
else
    printf '\033[31m%d of %d asserts failed.\033[0m\n' "$TESTS_FAILED" "$TESTS_RUN"; exit 1
fi
