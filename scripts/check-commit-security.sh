#!/bin/sh
set -eu

fail=0

say_fail() {
  printf '%s\n' "security check failed: $1" >&2
  fail=1
}

staged_files=$(git diff --cached --name-only --diff-filter=ACMR)

if [ -z "$staged_files" ]; then
  exit 0
fi

# Flag real local/private files, but allow the public .env.example template (whitelisted in .gitignore).
printf '%s\n' "$staged_files" | grep -E '(^|/)(\.env|\.env\..*|secrets/|\.claude/|\.impeccable/)' 2>/dev/null \
  | grep -vE '(^|/)\.env\.example$' | grep -q . \
  && say_fail "staged local/private project files"

printf '%s\n' "$staged_files" | grep -E '\.(pem|key|p12|pfx|crt|cer|csr|jks|keystore)$' >/dev/null 2>&1 \
  && say_fail "staged certificate, key, or keystore material"

for file in $staged_files; do
  [ -f "$file" ] || continue

  bytes=$(wc -c < "$file" | tr -d ' ')
  if [ "$bytes" -gt 1048576 ]; then
    printf '%s\n' "security check failed: large file staged: $file" >&2
    fail=1
  fi

  if grep -I -E '(-----BEGIN (RSA |EC |OPENSSH |DSA |)PRIVATE KEY-----|ghp_[A-Za-z0-9_]{20,}|github_pat_[A-Za-z0-9_]{20,}|AKIA[0-9A-Z]{16}|xox[baprs]-[A-Za-z0-9-]{10,})' "$file" >/dev/null 2>&1; then
    printf '%s\n' "security check failed: possible secret in $file" >&2
    fail=1
  fi
done

exit "$fail"
