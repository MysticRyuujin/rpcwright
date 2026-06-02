#!/usr/bin/env bash
# Validate the rpcwright skill: frontmatter, mirror symlinks, and link integrity.
# Run locally with: bash scripts/validate.sh
set -uo pipefail
cd "$(dirname "$0")/.."
fail=0

# 1. SKILL.md must start with YAML frontmatter containing name + description.
if ! head -1 SKILL.md | grep -qx -- '---'; then
  echo "FAIL: SKILL.md must start with '---' frontmatter"; fail=1
fi
if ! awk 'NR>1 && $0=="---"{exit} /^name:/{n=1} /^description:/{d=1} END{exit !(n&&d)}' SKILL.md; then
  echo "FAIL: SKILL.md frontmatter must include 'name:' and 'description:'"; fail=1
fi

# 2. AGENTS.md, CLAUDE.md, llms.txt are symlinks to SKILL.md (single source of truth,
#    no drift). See README/CONTRIBUTING for why symlinks (not copies).
for m in AGENTS.md CLAUDE.md llms.txt; do
  if [ ! -L "$m" ]; then
    echo "FAIL: $m must be a symlink to SKILL.md (run: ln -sf SKILL.md $m)"; fail=1
  elif [ "$(readlink "$m")" != "SKILL.md" ]; then
    echo "FAIL: $m must point to SKILL.md (points to '$(readlink "$m")')"; fail=1
  fi
done

# 3. Every relative markdown link resolves (catch renamed/removed reference files).
while IFS= read -r f; do
  d=$(dirname "$f")
  while IFS= read -r link; do
    case "$link" in http*|'#'*|mailto:*|'') continue ;; esac
    t="${link%%#*}"                 # strip #anchor
    [ -z "$t" ] && continue
    case "$t" in http*) continue ;; esac
    if [ ! -e "$d/$t" ]; then
      echo "FAIL: broken link in $f -> $link"; fail=1
    fi
  done < <(grep -oE '\]\([^) ]+\)' "$f" | sed -E 's/^\]\(//; s/\)$//')
done < <(find . -name '*.md' -not -path './.git/*')

if [ "$fail" -eq 0 ]; then
  echo "rpcwright: all checks passed"
else
  echo "rpcwright: validation FAILED"; exit 1
fi
