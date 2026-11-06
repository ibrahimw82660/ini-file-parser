#!/usr/bin/env bash
# ini_file_parser.sh - parse INI files into section.key=value pairs.
#
# Design choices:
# - The parser is line-oriented and stateful: it tracks the current section
#   as it streams over the file. This keeps the implementation small and makes
#   the section.key flattening rule obvious.
# - Keys before any section header are stored under the empty string prefix,
#   i.e. "key" rather than "section.key". This matches the common INI
#   convention that global keys are allowed and avoids inventing a magic
#   section name like "default" that could collide with a real section.
# - Quoted values are unquoted only when the first non-space character of the
#   value is a single or double quote and the matching quote is the last
#   non-space character. A quote in the middle of an unquoted value is kept
#   literally, because INI has no escape syntax and guessing would corrupt data.
# - Inline comments are only recognised when the ';' or '#' is preceded by
#   whitespace. This means "a#b" is a value, not a comment, which is the
#   behaviour most INI consumers rely on.

set -euo pipefail

# Trim leading and trailing whitespace (spaces and tabs) from a string.
# Usage: _ini_trim "$input"
_ini_trim() {
    local s="$1"
    # Leading whitespace: strip greedily.
    s="${s#"${s%%[![:space:]]*}"}"
    # Trailing whitespace: strip greedily.
    s="${s%"${s##*[![:space:]]}"}"
    printf '%s' "$s"
}

# Remove a trailing inline comment from a value string.
# A comment starts at ';' or '#' only when preceded by whitespace, so
# "value#fragment" and "value;fragment" are preserved intact.
# Usage: _ini_strip_inline_comment "$value"
_ini_strip_inline_comment() {
    local s="$1"
    local out=""
    local i ch prev
    local len=${#s}
    prev=""
    for ((i = 0; i < len; i++)); do
        ch="${s:i:1}"
        if [[ ( "$ch" == ';' || "$ch" == '#' ) && ( "$prev" == ' ' || "$prev" == $'\t' ) ]]; then
            break
        fi
        out+="$ch"
        prev="$ch"
    done
    printf '%s' "$out"
}

# Unquote a value if it is fully wrapped in matching single or double quotes.
# The quotes must be the first and last non-space characters. Interior quotes
# are kept as-is because INI has no escaping convention we can rely on.
# Usage: _ini_unquote "$value"
_ini_unquote() {
    local s
    s="$(_ini_trim "$1")"
    local len=${#s}
    if (( len >= 2 )); then
        local first="${s:0:1}"
        local last="${s:len-1:1}"
        if [[ "$first" == '"' && "$last" == '"' ]]; then
            printf '%s' "${s:1:len-2}"
            return 0
        fi
        if [[ "$first" == "'" && "$last" == "'" ]]; then
            printf '%s' "${s:1:len-2}"
            return 0
        fi
    fi
    printf '%s' "$s"
}

# Parse an INI file and print one flattened assignment per line as
# section.key=value. Global keys (before any section header) are printed as
# key=value. Blank lines and full-line comments are skipped.
#
# Usage: ini_parse_file /path/to/file.ini
ini_parse_file() {
    local file="$1"
    if [[ ! -f "$file" ]]; then
        printf 'ini_parse_file: no such file: %s\n' "$file" >&2
        return 1
    fi

    local section=""
    local line trimmed
    while IFS= read -r line || [[ -n "$line" ]]; do
        # Strip a trailing carriage return so CRLF files parse cleanly.
        line="${line%$'\r'}"
        trimmed="$(_ini_trim "$line")"

        # Blank line.
        if [[ -z "$trimmed" ]]; then
            continue
        fi

        # Full-line comment.
        if [[ "${trimmed:0:1}" == ';' || "${trimmed:0:1}" == '#' ]]; then
            continue
        fi

        # Section header.
        if [[ "${trimmed:0:1}" == '[' ]]; then
            if [[ "${trimmed: -1}" != ']' ]]; then
                printf 'ini_parse_file: malformed section header: %s\n' "$line" >&2
                return 1
            fi
            section="${trimmed:1:${#trimmed}-2}"
            section="$(_ini_trim "$section")"
            continue
        fi

        # Key=value line. Split on the first '='.
        if [[ "$trimmed" != *'='* ]]; then
            printf 'ini_parse_file: line is neither a section nor a key=value pair: %s\n' "$line" >&2
            return 1
        fi
        local key="${trimmed%%=*}"
        local value="${trimmed#*=}"
        key="$(_ini_trim "$key")"
        if [[ -z "$key" ]]; then
            printf 'ini_parse_file: empty key in line: %s\n' "$line" >&2
            return 1
        fi

        value="$(_ini_strip_inline_comment "$value")"
        value="$(_ini_unquote "$value")"

        if [[ -n "$section" ]]; then
            printf '%s.%s=%s\n' "$section" "$key" "$value"
        else
            printf '%s=%s\n' "$key" "$value"
        fi
    done < "$file"
}

# Look up a single flattened key in an INI file and print its value.
# Returns 1 when the key is absent. This is a convenience wrapper so callers
# do not have to grep the flattened output themselves.
#
# Usage: ini_get /path/to/file.ini section.key
ini_get() {
    local file="$1"
    local want="$2"
    local line
    while IFS= read -r line; do
        if [[ "${line%%=*}" == "$want" ]]; then
            printf '%s\n' "${line#*=}"
            return 0
        fi
    done < <(ini_parse_file "$file")
    return 1
}
