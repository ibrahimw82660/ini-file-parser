# ini-file-parser

Parse an INI file into flattened `section.key=value` pairs, with support for comments, blank lines, and quoted values.

```bash
source ini_file_parser.sh

cat > app.ini <<'EOF'
; global settings
name = demo

[server]
host = "localhost"
port = 8080   ; inline comment
EOF

ini_parse_file app.ini
# name=demo
# server.host=localhost
# server.port=8080

ini_get app.ini server.port
# 8080
```

## Why this exists

Most INI parsers in shell are `grep`/`sed` pipelines that break on quoted values, inline comments, or keys that appear before the first section header. This library keeps the parser in pure Bash so it can be sourced without installing anything, and it makes one deliberate flattening decision: keys before any `[section]` header are emitted without a prefix (`key=value`), while keys inside a section are emitted as `section.key=value`. That avoids inventing a magic section name such as `default` that could collide with a real section in the file.

## The awkward edge

Inline comments are recognised only when the `;` or `#` is preceded by whitespace. A value like `a#b` is therefore kept as `a#b`, not truncated to `a`. This is the behaviour most INI consumers rely on, but it means `k = v;comment` (no space before `;`) keeps the whole `v;comment` as the value. Put a space before the comment marker if you want it stripped.

## API

- `ini_parse_file FILE` — print one `section.key=value` (or `key=value` for global keys) line per entry. Returns non-zero on a missing file, a malformed section header, a line with no `=`, or an empty key.
- `ini_get FILE KEY` — print the value for the flattened `KEY` (for example `server.port`), or return 1 if it is absent.
