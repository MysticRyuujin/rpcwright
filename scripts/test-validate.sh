#!/usr/bin/env bash
set -euo pipefail

test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT
mkdir "$test_dir/scripts"
cp "$(dirname "$0")/validate.sh" "$test_dir/scripts/validate.sh"
cat > "$test_dir/SKILL.md" <<'EOF'
---
name: rpcwright
description: Validate Ethereum JSON-RPC changes.
---
EOF
for mirror in AGENTS.md CLAUDE.md llms.txt; do
  ln -s SKILL.md "$test_dir/$mirror"
done

bash "$test_dir/scripts/validate.sh"
sed '$d' "$test_dir/SKILL.md" > "$test_dir/incomplete"
mv "$test_dir/incomplete" "$test_dir/SKILL.md"
if bash "$test_dir/scripts/validate.sh" > "$test_dir/result" 2>&1; then
  echo "FAIL: validator accepts unclosed frontmatter"
  exit 1
fi
grep -q "closing '---'" "$test_dir/result"
echo "rpcwright: validator regression check passed"
