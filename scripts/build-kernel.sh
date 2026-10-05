#!/bin/bash
# Assembles the DeepSeek Harness that ships inside the app for command mode: a
# pinned Node.js runtime, VibeWand's coordinator bundle with the packages its
# rows name (kernel/coordinator, through kernel/package.json), and the harness's
# launcher. Everything fetched is checked against a pinned digest, no package
# script is run, and the result must boot before it is published.
set -euo pipefail
task_root="$(cd "$(dirname "$0")/.." && pwd)"
task_out="${VIBEWAND_KERNEL_PATH:-$task_root/output/kernel}"

task_node_version=24.21.0
task_node_sha256=6239d4cf92d864487ec8cd3615038f7b67e7f58b77b21cd2f09ea9fbd68065fe
# The launcher's own dependency list is the whole product. Only the launcher is
# taken; the packages it needs to start a profile are in kernel/package.json.
task_launcher=@deepseek-ai/dsh@0.2.0-rc.2
task_launcher_integrity='sha512-EAJ3gPNcVt/uv8X19PMm9NkVhWgT7xXNMk0UKCVm+IQ5rpSQOcsMUa0HWlnYYVybKMsccjcRB21vVVsaXQ6IdA=='

if [ "$(uname -m)" != "arm64" ]; then
  printf '%s\n' 'The bundled kernel is assembled for Apple Silicon only.' >&2
  exit 1
fi

# Reuse an earlier assembly unless what defines it has changed; the coordinator bundle is always refreshed.
task_stamp="$(cat "$task_root/kernel/package-lock.json" "$task_root/kernel/smoke.mjs" "$0" | shasum -a 256 | cut -d' ' -f1)"
if [ -f "$task_out/.stamp" ] && [ "$(cat "$task_out/.stamp")" = "$task_stamp" ]; then
  rm -rf "$task_out/node_modules/vibewand-coordinator"
  cp -R "$task_root/kernel/coordinator" "$task_out/node_modules/vibewand-coordinator"
  printf '%s\n' "$task_out"
  exit 0
fi

mkdir -p "$(dirname "$task_out")"
task_stage="$(mktemp -d "$(dirname "$task_out")/.kernel-build.XXXXXX")"
trap 'rm -rf "$task_stage"' EXIT
task_kernel="$task_stage/kernel"
mkdir -p "$task_kernel/node/bin"

task_node_name="node-v$task_node_version-darwin-arm64"
curl -fsSL "https://nodejs.org/dist/v$task_node_version/$task_node_name.tar.xz" -o "$task_stage/node.tar.xz"
printf '%s  %s\n' "$task_node_sha256" "$task_stage/node.tar.xz" | shasum -a 256 -c - >/dev/null
tar -xJf "$task_stage/node.tar.xz" -C "$task_stage"
cp "$task_stage/$task_node_name/bin/node" "$task_kernel/node/bin/node"
cp "$task_stage/$task_node_name/LICENSE" "$task_kernel/node/LICENSE"

# The runtime's own npm does the install, so the build needs no Node of its own.
task_npm() { "$task_stage/$task_node_name/bin/node" "$task_stage/$task_node_name/lib/node_modules/npm/bin/npm-cli.js" "$@"; }
cp "$task_root/kernel/package.json" "$task_root/kernel/package-lock.json" "$task_root/kernel/.npmrc" "$task_kernel/"
cp -R "$task_root/kernel/coordinator" "$task_kernel/coordinator"
(cd "$task_kernel" && task_npm ci --omit=dev --ignore-scripts --no-audit --no-fund >/dev/null)
# The bundle is now in node_modules as its own files. Command shims are symbolic links nothing here calls.
rm -rf "$task_kernel/coordinator" "$task_kernel/.npmrc" "$task_kernel/node_modules/.bin"

(cd "$task_stage" && task_npm pack "$task_launcher" --silent >/dev/null)
task_tarball="$(ls "$task_stage"/deepseek-ai-dsh-*.tgz)"
task_digest="sha512-$(openssl dgst -sha512 -binary "$task_tarball" | base64 | tr -d '\n')"
if [ "$task_digest" != "$task_launcher_integrity" ]; then
  printf 'Launcher digest mismatch: expected %s, got %s\n' "$task_launcher_integrity" "$task_digest" >&2
  exit 1
fi
mkdir -p "$task_kernel/node_modules/@deepseek-ai/dsh"
tar -xzf "$task_tarball" --strip-components=1 -C "$task_kernel/node_modules/@deepseek-ai/dsh"

"$task_kernel/node/bin/node" "$task_root/kernel/smoke.mjs" "$task_kernel"

printf '%s\n' "$task_stamp" > "$task_kernel/.stamp"
rm -rf "$task_out"
mv "$task_kernel" "$task_out"
printf '%s\n' "$task_out"
