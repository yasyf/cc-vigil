#!/usr/bin/env bash
set -euo pipefail

workflow=.github/workflows/release.yml
pin=19c3d5013032ad9c88f9a8f1170d1f366c19b8d9

if grep -Eq 'yasyf/homebrew-tap/.+@(v[0-9]+|main|swift-v[0-9]+)' "$workflow"; then
  echo "homebrew-tap release actions must use an exact commit" >&2
  exit 1
fi
test "$(grep -Ec "uses: yasyf/homebrew-tap/.+@${pin}$" "$workflow")" = 5
if grep -Eq 'softprops/action-gh-release|attach-to-release' "$workflow"; then
  echo "signing actions must not publish releases" >&2
  exit 1
fi

for required in \
  'name: Test CCVigilShared' \
  'name: Smoke-test the staged app archive' \
  'name: Stage and verify the complete draft release' \
  'gh release download "$TAG"' \
  'shasum -a 256 -c' \
  'name: Publish the verified release' \
  'name: Publish the cask to the tap'; do
  grep -Fq "$required" "$workflow"
done

line() { grep -Fn "$1" "$workflow" | cut -d: -f1; }
smoke="$(line 'name: Smoke-test the staged app archive')"
stage="$(line 'name: Stage and verify the complete draft release')"
publish="$(line 'name: Publish the verified release')"
cask="$(line 'name: Publish the cask to the tap')"
test "$smoke" -lt "$stage"
test "$stage" -lt "$publish"
test "$publish" -lt "$cask"
