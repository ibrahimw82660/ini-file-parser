#!/usr/bin/env bash
# Tests for ini_file_parser.sh. Run with: bash test_ini_file_parser.sh

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=ini_file_parser.sh
source "$HERE/ini_file_parser.sh"

TEST_COUNT=0
FAIL_COUNT=0

assert_eq() {
    local expected="$1"
    local actual="$2"
    local label="$3"
    TEST_COUNT=$((TEST_COUNT + 1))
    if [[ "$expected" == "$actual" ]]; then
        printf 'ok %d - %s\n' "$TEST_COUNT" "$label"
    else
        printf 'not ok %d - %s\n' "$TEST_COUNT" "$label"
        printf '  expected: %q\n' "$expected"
        printf '  actual:   %q\n' "$actual"
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
}

TMPDIR_TEST="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_TEST"' EXIT

write_ini() {
    local path="$1"
    shift
    printf '%s\n' "$@" > "$path"
}

# 1. Basic section and key parsing.
write_ini "$TMPDIR_TEST/basic.ini" \
    '[server]' \
    'host = localhost' \
    'port=8080'
assert_eq $'server.host=localhost\nserver.port=8080' "$(ini_parse_file "$TMPDIR_TEST/basic.ini")" 'basic section and keys'

# 2. Global keys before any section header keep no prefix.
write_ini "$TMPDIR_TEST/global.ini" \
    'name = global' \
    '[section]' \
    'name = local'
assert_eq $'name=global\nsection.name=local' "$(ini_parse_file "$TMPDIR_TEST/global.ini")" 'global keys are unprefixed'

# 3. Blank lines and full-line comments are skipped.
write_ini "$TMPDIR_TEST/comments.ini" \
    '; a comment' \
    '' \
    '# another comment' \
    '[s]' \
    'k = v'
assert_eq 's.k=v' "$(ini_parse_file "$TMPDIR_TEST/comments.ini")" 'comments and blank lines skipped'

# 4. Inline comments are stripped when preceded by whitespace.
write_ini "$TMPDIR_TEST/inline.ini" \
    '[s]' \
    'k = value ; trailing comment' \
    'j = other # comment'
assert_eq $'s.k=value\ns.j=other' "$(ini_parse_file "$TMPDIR_TEST/inline.ini")" 'inline comments stripped'

# 5. A hash or semicolon inside a value without preceding space is data.
write_ini "$TMPDIR_TEST/hash.ini" \
    '[s]' \
    'k = a#b' \
    'j = c;d'
assert_eq $'s.k=a#b\ns.j=c;d' "$(ini_parse_file "$TMPDIR_TEST/hash.ini")" 'hash and semicolon inside value preserved'

# 6. Double-quoted values are unquoted.
write_ini "$TMPDIR_TEST/dquote.ini" \
    '[s]' \
    'k = "hello world"'
assert_eq 's.k=hello world' "$(ini_parse_file "$TMPDIR_TEST/dquote.ini")" 'double-quoted value unquoted'

# 7. Single-quoted values are unquoted.
write_ini "$TMPDIR_TEST/squote.ini" \
    '[s]' \
    "k = 'hello world'"
assert_eq 's.k=hello world' "$(ini_parse_file "$TMPDIR_TEST/squote.ini")" 'single-quoted value unquoted'

# 8. Mismatched quotes are left alone.
write_ini "$TMPDIR_TEST/mismatch.ini" \
    '[s]' \
    'k = "hello' \
    "j = 'world"
assert_eq $'s.k="hello\ns.j=\x27world' "$(ini_parse_file "$TMPDIR_TEST/mismatch.ini")" 'mismatched quotes preserved'

# 9. A quote in the middle of an unquoted value is kept literally.
write_ini "$TMPDIR_TEST/midquote.ini" \
    '[s]' \
    'k = a"b"c'
assert_eq 's.k=a"b"c' "$(ini_parse_file "$TMPDIR_TEST/midquote.ini")" 'interior quotes preserved'

# 10. Whitespace around keys and values is trimmed.
write_ini "$TMPDIR_TEST/trim.ini" \
    '  [s]  ' \
    '  k   =   v  '
assert_eq 's.k=v' "$(ini_parse_file "$TMPDIR_TEST/trim.ini")" 'whitespace trimmed'

# 11. CRLF line endings are handled.
printf '[s]\r\nk = v\r\n' > "$TMPDIR_TEST/crlf.ini"
assert_eq 's.k=v' "$(ini_parse_file "$TMPDIR_TEST/crlf.ini")" 'CRLF line endings'

# 12. ini_get returns the value for a flattened key.
write_ini "$TMPDIR_TEST/get.ini" \
    '[s]' \
    'k = v'
assert_eq 'v' "$(ini_get "$TMPDIR_TEST/get.ini" 's.k')" 'ini_get finds key'

# 13. ini_get returns non-zero for a missing key.
set +e
ini_get "$TMPDIR_TEST/get.ini" 's.missing' >/dev/null 2>&1
rc=$?
set -e
assert_eq '1' "$rc" 'ini_get missing key returns 1'

# 14. A malformed section header is an error.
write_ini "$TMPDIR_TEST/bad.ini" \
    '[s' \
    'k = v'
set +e
ini_parse_file "$TMPDIR_TEST/bad.ini" >/dev/null 2>&1
rc=$?
set -e
assert_eq '1' "$rc" 'malformed section header fails'

# 15. A line without '=' is an error.
write_ini "$TMPDIR_TEST/bad2.ini" \
    '[s]' \
    'just a line'
set +e
ini_parse_file "$TMPDIR_TEST/bad2.ini" >/dev/null 2>&1
rc=$?
set -e
assert_eq '1' "$rc" 'line without equals fails'

# 16. A missing file is an error.
set +e
ini_parse_file "$TMPDIR_TEST/does-not-exist.ini" >/dev/null 2>&1
rc=$?
set -e
assert_eq '1' "$rc" 'missing file fails'

printf '1..%d\n' "$TEST_COUNT"
if (( FAIL_COUNT > 0 )); then
    printf '# %d test(s) failed\n' "$FAIL_COUNT"
    exit 1
fi
printf '# all tests passed\n'
