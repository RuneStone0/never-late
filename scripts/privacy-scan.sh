#!/bin/bash
# Scans tracked files and the full git history for personal or work-related data before anything is pushed.
# Built-in patterns are generic. Add your own (employer names, internal hostnames, ...) one regex per line to
# .privacy-patterns.local, which is gitignored so the terms themselves never end up in this public repo.
# Exits non-zero if anything matches.
set -uo pipefail
cd "$(dirname "$0")/.."

patterns=(
    '/Users/[A-Za-z0-9._-]+'                                    # absolute home paths
    '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}'            # email addresses (noreply is filtered below)
    '(ghp|gho|ghs|github_pat)_[A-Za-z0-9_]{20,}'                # GitHub tokens
    'AKIA[0-9A-Z]{16}'                                          # AWS access keys
    '-----BEGIN [A-Z ]*PRIVATE KEY-----'                        # private keys
    '(api[_-]?key|secret|token|password)[[:space:]]*[:=][[:space:]]*["'\''][^"'\'']{8,}'
    '\b(10\.[0-9]+|192\.168|172\.(1[6-9]|2[0-9]|3[01]))\.[0-9]+\.[0-9]+\b'   # private IPs
)
if [ -f .privacy-patterns.local ]; then
    while IFS= read -r line; do
        [ -n "$line" ] && [[ "$line" != \#* ]] && patterns+=("$line")
    done < .privacy-patterns.local
else
    echo "note: no .privacy-patterns.local; only generic patterns are checked" >&2
fi

# The scanner and its docs mention these patterns by design.
exclude=(':!scripts/privacy-scan.sh' ':!AGENTS.md')
status=0

check() {
    local label=$1 pattern=$2 hits
    hits=$(git grep -nIiE "$pattern" -- . "${exclude[@]}" 2>/dev/null \
        | grep -viE 'noreply\.github\.com|user@example\.com|@example\.(com|org)' || true)
    if [ -n "$hits" ]; then
        echo "FOUND in working tree [$pattern]:"; echo "$hits" | sed 's/^/  /'; status=1
    fi
    hits=$(git log --all -p --no-color -G"$pattern" --pickaxe-regex -i --format='commit %h' -- . "${exclude[@]}" 2>/dev/null \
        | grep -iE "^[+-].*($pattern)|^commit " | grep -iB1 -E "^[+-]" | grep -viE 'noreply\.github\.com|@example\.' | grep -v '^--$' || true)
    if echo "$hits" | grep -qE '^[+-]'; then
        echo "FOUND in history [$pattern]:"; echo "$hits" | sed 's/^/  /' | head -20; status=1
    fi
}

for p in "${patterns[@]}"; do check "$p" "$p"; done

# Commit identities must be the noreply address, never a work or personal inbox.
bad=$(git log --all --format='%an <%ae>%n%cn <%ce>' | sort -u | grep -v 'noreply\.github\.com' || true)
if [ -n "$bad" ]; then echo "FOUND non-noreply commit identity:"; echo "$bad" | sed 's/^/  /'; status=1; fi

[ $status -eq 0 ] && echo "PASS: no matches" || echo "FAIL: review the matches above before pushing" >&2
exit $status
