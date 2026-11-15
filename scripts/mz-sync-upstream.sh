#!/usr/bin/env bash
# Sinkron fork CodeBuddy (mzaimilzam/9router) ke tag upstream baru.
# Patch kita disimpan content-based di patches/codebuddy-identity.patch, jadi
# tiap rilis upstream = satu perintah, bukan merge buntu.
#
# Pakai:  scripts/mz-sync-upstream.sh v0.5.120
# Hasil:  worktree /tmp/9r-sync di tag upstream + patch, commit + tag v0.5.120-mz
#         patch diperbarui otomatis untuk rilis berikutnya
set -euo pipefail

TAG="${1:?pakai: scripts/mz-sync-upstream.sh v0.5.120}"
VER="${TAG#v}-mz"                 # versi rilis kita, mis. 0.5.120-mz
ROOT="$(git -C "$(dirname "$0")/.." rev-parse --show-toplevel)"
cd "$ROOT"
UP="up/$TAG"
WT="/tmp/9r-sync"
PATCH="$ROOT/patches/codebuddy-identity.patch"
# package.json sengaja di luar patch: versi diurus langkah 5 (CI menuntut root == cli)
EXCLUDE=(':(exclude)package.json' ':(exclude)cli/package.json')

git fetch origin 'refs/tags/*:refs/tags/up/*' --no-tags >/dev/null
git rev-parse --verify "$UP^{commit}" >/dev/null

git worktree remove --force "$WT" 2>/dev/null || true
git worktree add -f --detach "$WT" "$UP" >/dev/null
cd "$WT"
ln -sfn "$ROOT/node_modules" node_modules

# patch content-based, 3-way biar drift upstream ter-merge otomatis
if ! git apply --3way "$PATCH"; then
  echo "KONFLIK — selesaikan manual:"
  git status --short | grep -E '^(UU|AA|DU|UD)' || true
  cat <<EOF

Langkah lanjut setelah konflik dibereskan:
  cd $WT
  node tests/__baseline__/snapshot-providers.mjs   # snapshot generated, jangan di-merge tangan
  git add -A && git commit -m "chore(rebase): CodeBuddy identity patch onto upstream $TAG"
  git tag -f $VER
  git diff $UP $VER -- ':(exclude)package.json' ':(exclude)cli/package.json' > $PATCH
EOF
  exit 1
fi

# snapshot registry itu generated — selalu regenerasi, jangan merge tangan
node tests/__baseline__/snapshot-providers.mjs >/dev/null 2>&1
node tests/__baseline__/verify-providers.mjs 2>/dev/null | grep -E '✅|❌|MISMATCH' || true

# JEBAKAN yang pernah kejadian: upstream menghapus simbol yang dipakai hunk kita.
# 3-way apply tetap "bersih" karena definisinya di luar konteks hunk -> baru
# ketahuan saat call pertama (ReferenceError). Cek cepat sebelum rilis:
grep -n 'const originalFetch' open-sse/utils/proxyFetch.js \
  || { echo "PERINGATAN: originalFetch tak terdefinisi (upstream menghapusnya?) — tambahkan:"; \
       echo '  const originalFetch = globalThis.fetch;   // sebelum patchedFetch menimpa globalThis.fetch'; }

# versi root + cli wajib sama & sinkron dengan tag, kalau tidak CI Docker menolak
python3 - "$VER" <<'PY'
import json, sys
ver = sys.argv[1]
for p in ("package.json", "cli/package.json"):
    d = json.load(open(p, encoding="utf-8"))
    d["version"] = ver
    with open(p, "w", encoding="utf-8") as f:
        json.dump(d, f, indent=2, ensure_ascii=False)
        f.write("\n")
print("  versi diset:", ver)
PY

git checkout -q -b "mz/$TAG"
git add -A
git -c user.name='mzaimilzam' -c user.email='mzaimilzam@users.noreply.github.com' \
  commit -q -m "chore(rebase): CodeBuddy identity patch onto upstream $TAG"
git tag -f "$VER"

git diff "$UP" "$VER" "${EXCLUDE[@]}" > "$PATCH"
echo "SELESAI: cabang mz/$TAG, tag $VER (worktree: $WT), patch $(wc -l < "$PATCH") baris"
cat <<EOF

Rilis + deploy (tag GHCR = versi TANPA huruf v):
  git -c credential.helper='!f(){ echo username=x-access-token; echo password="\$GH_PAT"; };f' \\
      push fork "mz/$TAG" "$VER"
  # tunggu CI 'Build and Push Docker Image' sukses, lalu arahkan Coolify ke $VER:
  python3 scripts/mz-deploy.py $VER
  # WAJIB uji inferensi live sesudahnya — rebase bisa lolos CI tapi meledak saat call:
  python3 /tmp/r9_models.py "tokenharbor/deepseek-v4.1-flash:free" "cbai/glm-5.2"

Catatan: cbai/* balas 403 code 11140 "request illegal" itu BANNED DARI SONONYA
(provider/WAF Tencent) — terbukti sama di 0.5.113 & 0.5.119-mz.1. Jangan diselidiki
lagi sebagai bug rebase.
EOF
