#!/usr/bin/env bash
# Sinkron fork CodeBuddy (mzaimilzam/9router) ke tag upstream baru.
# Patch kita disimpan content-based di patches/codebuddy-identity.patch, jadi
# tiap rilis upstream = satu perintah, bukan merge buntu.
#
# Pakai:  scripts/mz-sync-upstream.sh v0.5.120
# Hasil:  worktree /tmp/9r-sync di tag upstream + patch, commit + tag v0.5.120-mz
set -euo pipefail

TAG="${1:?pakai: scripts/mz-sync-upstream.sh v0.5.120}"
ROOT="$(git -C "$(dirname "$0")/.." rev-parse --show-toplevel)"
cd "$ROOT"
UP="up/$TAG"
WT="/tmp/9r-sync"
PATCH="$ROOT/patches/codebuddy-identity.patch"

# 1. tarik tag upstream ke namespace up/* (tag lokal kita tak pernah tertimpa)
git fetch origin 'refs/tags/*:refs/tags/up/*' --no-tags >/dev/null
git rev-parse --verify "$UP^{commit}" >/dev/null

# 2. worktree bersih di tag upstream
git worktree remove --force "$WT" 2>/dev/null || true
git worktree add -f --detach "$WT" "$UP" >/dev/null
cd "$WT"
ln -sfn "$ROOT/node_modules" node_modules

# 3. patch content-based, 3-way biar drift upstream ter-merge otomatis
if ! git apply --3way "$PATCH"; then
  echo "KONFLIK — selesaikan manual:"
  git status --short | grep -E '^(UU|AA|DU|UD)' || true
  cat <<EOF

Langkah lanjut setelah konflik dibereskan:
  cd $WT
  node tests/__baseline__/snapshot-providers.mjs   # snapshot generated, jangan di-merge tangan
  git add -A && git commit -m "chore(rebase): CodeBuddy identity patch onto upstream $TAG"
  git tag -f $TAG-mz
  git diff $UP $TAG-mz > $PATCH             # patch diperbarui untuk rilis berikutnya
EOF
  exit 1
fi

# 4. snapshot registry itu generated — selalu regenerasi, jangan merge tangan
node tests/__baseline__/snapshot-providers.mjs >/dev/null 2>&1
node tests/__baseline__/verify-providers.mjs 2>/dev/null | grep -E '✅|❌|MISMATCH' || true

# 5. commit + tag
git checkout -q -b "mz/$TAG"
git add -A
git -c user.name='mzaimilzam' -c user.email='mzaimilzam@users.noreply.github.com' \
  commit -q -m "chore(rebase): CodeBuddy identity patch onto upstream $TAG"
git tag -f "$TAG-mz"

echo "SELESAI: cabang mz/$TAG, tag $TAG-mz (worktree: $WT)"
echo "Patch diperbarui untuk rilis berikutnya:"
git diff "$UP" "$TAG-mz" > "$PATCH"
wc -l < "$PATCH" | xargs echo "  baris patch:"
