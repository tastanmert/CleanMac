#!/bin/zsh
# Copies the current commit to the public repository (tastanmert/CleanMac) as one new commit on its main branch.
# Internal files stay out: maintainer notes, assistant settings and the internal review document.
set -euo pipefail
cd "$(dirname "$0")/.."

MESSAGE="${1:?commit message, e.g. \"CleanMac 1.5\"}"
REMOTE="https://github.com/tastanmert/CleanMac.git"
EXCLUDE=(CLAUDE.md .claude docs/*-inceleme.md)

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
if git ls-remote --exit-code "$REMOTE" main >/dev/null 2>&1; then
  git clone --quiet --depth 1 "$REMOTE" "$WORK/repo"
else
  git init --quiet -b main "$WORK/repo"
  git -C "$WORK/repo" remote add origin "$REMOTE"
fi

# Replace the tree with HEAD's files, minus the internal ones.
git -C "$WORK/repo" rm -rq --ignore-unmatch . >/dev/null
git archive HEAD | tar -x -C "$WORK/repo"
for item in $EXCLUDE; do rm -rf "$WORK"/repo/${~item}; done

git -C "$WORK/repo" add -A
if git -C "$WORK/repo" diff --cached --quiet; then echo "Açık depo zaten güncel."; exit 0; fi
git -C "$WORK/repo" commit --quiet -m "$MESSAGE"
git -C "$WORK/repo" push --quiet origin main
echo "Açık depoya gönderildi: $MESSAGE"
