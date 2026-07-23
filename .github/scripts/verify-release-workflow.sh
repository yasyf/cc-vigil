#!/usr/bin/env bash
set -euo pipefail

workflow=.github/workflows/release.yml
action_pin=19c3d5013032ad9c88f9a8f1170d1f366c19b8d9
stage_pin=e4c3108e693681df1a3c666bae80e890bc44cf3e
draft_pin=54e3e194bda69896894a82c17fcdb2822beefab5
tap_pin=9ca67392d45d66b6ae01e262383c8f3138d56f5e

if grep -Eq 'yasyf/homebrew-tap/.+@(v[0-9]+|main|swift-v[0-9]+)' "$workflow"; then
  echo "homebrew-tap release actions must use an exact commit" >&2
  exit 1
fi
test "$(grep -Ec "uses: yasyf/homebrew-tap/.+@${action_pin}$" "$workflow")" = 4
test "$(grep -Ec "actions/stage-draft-release@${stage_pin}$" "$workflow")" = 1
test "$(grep -Ec "actions/publish-draft-release@${draft_pin}$" "$workflow")" = 1
test "$(grep -Ec "actions/publish@${tap_pin}$" "$workflow")" = 1
if grep -Eq 'softprops/action-gh-release|attach-to-release' "$workflow"; then
  echo "signing actions must not publish releases" >&2
  exit 1
fi

for required in \
  'name: Test CCVigilShared' \
  'name: Smoke-test the staged app archive' \
  'name: Stage and verify the complete draft release' \
  'name: Smoke-test the exact downloaded release' \
  'actions/stage-draft-release@' \
  'actions/publish-draft-release@' \
  'shasum -a 256 -c' \
  'name: Publish the verified release' \
  'name: Publish the cask to the tap'; do
  grep -Fq "$required" "$workflow"
done
if grep -Eq '/releases/tags/|gh release (view|upload|download|edit)' "$workflow"; then
  echo "release workflow must retain one exact numeric release ID" >&2
  exit 1
fi

line() { grep -Fn "$1" "$workflow" | cut -d: -f1; }
smoke="$(line 'name: Smoke-test the staged app archive')"
stage="$(line 'name: Stage and verify the complete draft release')"
publish="$(line 'name: Publish the verified release')"
cask="$(line 'name: Publish the cask to the tap')"
test "$smoke" -lt "$stage"
test "$stage" -lt "$publish"
test "$publish" -lt "$cask"
