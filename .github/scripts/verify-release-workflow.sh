#!/usr/bin/env bash
set -euo pipefail

workflow=.github/workflows/release.yml
tap_workflow=.github/workflows/publish-tap.yml
action_pin=19c3d5013032ad9c88f9a8f1170d1f366c19b8d9
stage_pin=e4c3108e693681df1a3c666bae80e890bc44cf3e
draft_pin=54e3e194bda69896894a82c17fcdb2822beefab5
tap_pin=9ca67392d45d66b6ae01e262383c8f3138d56f5e

if grep -Eq 'yasyf/homebrew-tap/.+@(v[0-9]+|main|swift-v[0-9]+)' "$workflow" "$tap_workflow"; then
  echo "homebrew-tap release actions must use an exact commit" >&2
  exit 1
fi
test "$(grep -Ec "uses: yasyf/homebrew-tap/.+@${action_pin}$" "$workflow")" = 3
test "$(grep -Ec "actions/stage-draft-release@${stage_pin}$" "$workflow")" = 1
test "$(grep -Ec "actions/publish-draft-release@${draft_pin}$" "$workflow")" = 1
test "$(grep -Ec "actions/publish@${tap_pin}$" "$tap_workflow")" = 1
test "$(grep -Fxc "          release-id: \${{ steps.draft.outputs['release-id'] }}" "$workflow")" = 1
if grep -Eq 'softprops/action-gh-release|attach-to-release' "$workflow" "$tap_workflow"; then
  echo "signing actions must not publish releases" >&2
  exit 1
fi
if grep -Eq 'HOMEBREW_TAP_TOKEN|actions/publish@|Render the cask|tap-staging' "$workflow"; then
  echo "release workflow must not render or mutate the tap" >&2
  exit 1
fi
if grep -Eq 'xcodebuild|notarytool|sign-notarize|stage-draft-release|publish-draft-release' "$tap_workflow"; then
  echo "tap delivery must not build, sign, notarize, or mutate a release" >&2
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
  'name: Publish the verified release'; do
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
test "$smoke" -lt "$stage"
test "$stage" -lt "$publish"

for required in \
  'workflow_dispatch:' \
  'release-id:' \
  'tagged-source-sha:' \
  'zip-sha256:' \
  'sidecar-sha256:' \
  'permissions:' \
  'contents: read' \
  'name: Verify the exact public release and render the tagged cask' \
  'run: python3 .github/scripts/prepare-public-tap.py' \
  'name: Publish only the verified cask'; do
  grep -Fq "$required" "$tap_workflow"
done
test "$(grep -Fc 'HOMEBREW_TAP_TOKEN' "$tap_workflow")" = 1
test "$(grep -Fc 'actions/publish@' "$tap_workflow")" = 1
test "$(grep -Fc 'uses: yasyf/homebrew-tap/' "$tap_workflow")" = 1
if grep -Eq '^  (push|release|workflow_run):' "$tap_workflow"; then
  echo "tap delivery must remain separately retryable and manually bound to immutable inputs" >&2
  exit 1
fi
