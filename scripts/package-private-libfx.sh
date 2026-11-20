#!/usr/bin/env bash
# Packs the Kai runtime's libfx for GitHub Packages as @kunemi-group/kai, checks the archives, and
# with --publish publishes them. Used by .github/workflows/publish-private-libfx.yml
# and, while hosted CI is unavailable, run by hand.
#
#   scripts/package-private-libfx.sh <addons-dir> <out-dir> [--publish]
#
# <addons-dir> holds libfx.<platform>.node for linux-x64, linux-arm64,
# darwin-x64 and darwin-arm64. zig-out/bin must hold fx-core.wasm and
# fx-term.wasm, built from the same commit.
#
# Environment:
#   LIBFX_VERSION   the version, such as 0.0.17-kai.1 (required)
#   LIBFX_SCOPE     the scope, default @kunemi-group (a GitHub organisation)
#   LIBFX_NAME      the package name, default kai
#   LIBFX_REGISTRY  default https://npm.pkg.github.com
#   NODE_AUTH_TOKEN a token with write:packages, for --publish only
#
# Every package is published in the scope (<name> and <name>-<platform>);
# libfx's optional dependencies are
# npm aliases under the @libfx/ names node.js loads. A version already in the
# registry is never published again, and its archive must match this one.
set -euo pipefail

addons=${1:?addons dir}
out=${2:?output dir}
publish=${3:-}
: "${LIBFX_VERSION:?set LIBFX_VERSION}"
export LIBFX_SCOPE=${LIBFX_SCOPE:-@kunemi-group}
export LIBFX_NAME=${LIBFX_NAME:-kai}
export LIBFX_REGISTRY=${LIBFX_REGISTRY:-https://npm.pkg.github.com}
root=$(cd "$(dirname "$0")/.." && pwd)
export LIBFX_SOURCE_COMMIT=${LIBFX_SOURCE_COMMIT:-$(git -C "$root" rev-parse HEAD)}

if [[ ! "$LIBFX_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+-kai\.[0-9]+$ ]]; then
  echo "LIBFX_VERSION must look like 0.0.17-kai.1: $LIBFX_VERSION" >&2
  exit 1
fi
if [ -n "$(git -C "$root" status --porcelain --untracked-files=no)" ]; then
  echo "the checkout has uncommitted changes; package from a clean commit" >&2
  exit 1
fi
for wasm in fx-core.wasm fx-term.wasm; do
  [ -f "$root/zig-out/bin/$wasm" ] || { echo "zig-out/bin/$wasm is missing" >&2; exit 1; }
done

mkdir -p "$out"
out=$(cd "$out" && pwd)
dist="$out/dist"
rm -rf "$dist" "$out/native" "$out"/*.tgz "$out/packages.sha256"
(cd "$root" && node sdk/scripts/package-libfx.mjs "$dist" "$addons"/libfx.*.node)

npm pack "$dist/libfx" --ignore-scripts --pack-destination "$out" --json > "$out/pack.json"
mkdir "$out/native"
for package in "$dist"/libfx-*/; do
  npm pack "$package" --ignore-scripts --pack-destination "$out/native" --json
done | jq -s add > "$out/native-pack.json"

# The archives: libfx in the scope, each platform package pinned by an alias
# at exactly this version, each holding only its addon and loader.
node - "$out" <<'EOF'
const { readFileSync } = require("node:fs");
const out = process.argv[2];
const scope = process.env.LIBFX_SCOPE, name = process.env.LIBFX_NAME, version = process.env.LIBFX_VERSION;
const main = JSON.parse(readFileSync(`${out}/pack.json`, "utf8"))[0];
const natives = JSON.parse(readFileSync(`${out}/native-pack.json`, "utf8"));
const manifest = JSON.parse(readFileSync(`${out}/dist/libfx/package.json`, "utf8"));
const fail = (message) => { console.error(message); process.exit(1); };
if (main.name !== `${scope}/${name}` || main.version !== version) fail(`unexpected ${main.name}@${main.version}`);
if (manifest.publishConfig?.registry !== process.env.LIBFX_REGISTRY) fail("libfx doesn't name the registry");
if (manifest.gitHead !== process.env.LIBFX_SOURCE_COMMIT) fail("libfx doesn't record its commit");
const pinned = manifest.optionalDependencies;
if (Object.keys(pinned).length !== 4) fail(`expected four platform packages: ${Object.keys(pinned)}`);
for (const [alias, spec] of Object.entries(pinned)) {
  if (!alias.startsWith("@libfx/")) fail(`${alias} is not an @libfx/ name`);
  const target = `${scope}/${alias.slice("@libfx/libfx".length).replace(/^/, name)}`;
  if (spec !== `npm:${target}@${version}`) fail(`${alias} pins ${spec}`);
  const report = natives.find(({ name }) => name === target);
  if (!report || report.version !== version) fail(`no archive for ${target}@${version}`);
  const files = report.files.map(({ path }) => path).sort().join();
  if (files !== "LICENSE,README.md,index.js,libfx.node,package.json") fail(`${target} has ${files}`);
}
for (const name of ["node.js", "engine.js", "durable.js", "fx-core.wasm", "fx-term.wasm"]) {
  if (!main.files.some(({ path }) => path === name)) fail(`libfx is missing ${name}`);
}
console.log(`validated ${main.name}@${main.version} and ${natives.length} platform packages`);
EOF
(cd "$out" && sha256sum ./*.tgz native/*.tgz > packages.sha256)

# The archive installs as `libfx` beside this machine's platform package under
# its @libfx/ name, as the aliases install it, and loads the native backend.
smoke=$(mktemp -d)
trap 'rm -rf "$smoke"' EXIT
platform=$(node -p 'process.platform + "-" + process.arch')
case "$platform" in
  linux-x64) local_name=linux-x64-gnu ;;
  linux-arm64) local_name=linux-arm64-gnu ;;
  darwin-x64) local_name=darwin-x64 ;;
  darwin-arm64) local_name=darwin-arm64 ;;
  *) echo "no platform package for $platform" >&2; exit 1 ;;
esac
local_archive=$(ls "$out/native/"*"-$LIBFX_NAME-$local_name-$LIBFX_VERSION.tgz")
main_archive=$(ls "$out/"*"-$LIBFX_NAME-$LIBFX_VERSION.tgz")
printf '{"private":true,"type":"module"}\n' > "$smoke/package.json"
(cd "$smoke" && npm install --ignore-scripts --no-audit --no-fund --omit=optional \
  "libfx@file:$main_archive" "@libfx/libfx-$local_name@file:$local_archive" > /dev/null)
# shellcheck disable=SC2016 # JavaScript, not shell
(cd "$smoke" && node --input-type=module -e '
  const { getBackendInfo } = await import("libfx");
  const info = await getBackendInfo();
  if (info.backend !== "native") throw new Error(`loaded ${JSON.stringify(info)}`);
  console.log(`installed and loaded the native backend: ${JSON.stringify(info)}`);
')

[ "$publish" = "--publish" ] || exit 0
: "${NODE_AUTH_TOKEN:?set NODE_AUTH_TOKEN to publish}"
host=${LIBFX_REGISTRY#https://}
npmrc="$smoke/.npmrc"
# shellcheck disable=SC2016 # npm reads the token from the environment itself
printf '%s:registry=%s\n//%s/:_authToken=${NODE_AUTH_TOKEN}\n' "$LIBFX_SCOPE" "$LIBFX_REGISTRY" "${host%/}" > "$npmrc"
published() { npm view "$1@$LIBFX_VERSION" version --userconfig "$npmrc" > /dev/null 2>&1; }
# Platform packages first: without them, installs of libfx fall back to WASM.
for archive in "$out"/native/*.tgz "$main_archive"; do
  name=$(tar -xzOf "$archive" package/package.json | jq -r .name)
  if published "$name"; then
    mkdir -p "$smoke/registry"
    got=$(npm pack "$name@$LIBFX_VERSION" --ignore-scripts --userconfig "$npmrc" --pack-destination "$smoke/registry" --json | jq -r '.[0].filename')
    cmp "$archive" "$smoke/registry/$got" || { echo "$name@$LIBFX_VERSION is already published with other contents" >&2; exit 1; }
    echo "$name@$LIBFX_VERSION is already published, unchanged"
    continue
  fi
  # Every Kai version is a prerelease of the fx version it builds on, and the only line published, so it is latest.
  npm publish "$archive" --tag latest --ignore-scripts --userconfig "$npmrc"
  echo "published $name@$LIBFX_VERSION"
done
