#!/usr/bin/env bash
# Packs the Kai runtime's fx command for GitHub Packages as
# @kunemi-group/kai-cli-linux-x64 and @kunemi-group/kai-cli-linux-arm64, and
# with --publish publishes them. Dotrix's coding image installs one and checks
# its binary's SHA-256, which it pins (infra/coding/Dockerfile). Used by
# .github/workflows/publish-private-libfx.yml and, while hosted CI is
# unavailable, run by hand.
#
#   scripts/package-private-cli.sh <bin-dir> <out-dir> [--publish]
#
# <bin-dir> holds fx-x86_64 and fx-aarch64: static Linux builds from this
# commit (zig build -Doptimize=ReleaseSafe -Dcpu=baseline
# -Dtarget=<arch>-linux-musl). The environment is as for
# package-private-libfx.sh: LIBFX_VERSION, LIBFX_SCOPE, LIBFX_NAME,
# LIBFX_REGISTRY and, to publish, NODE_AUTH_TOKEN.
set -euo pipefail

bins=${1:?bin dir}
out=${2:?output dir}
publish=${3:-}
: "${LIBFX_VERSION:?set LIBFX_VERSION}"
scope=${LIBFX_SCOPE:-@kunemi-group}
name=${LIBFX_NAME:-kai}
registry=${LIBFX_REGISTRY:-https://npm.pkg.github.com}
root=$(cd "$(dirname "$0")/.." && pwd)
commit=${LIBFX_SOURCE_COMMIT:-$(git -C "$root" rev-parse HEAD)}

if [[ ! "$LIBFX_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+-kai\.[0-9]+$ ]]; then
  echo "LIBFX_VERSION must look like 0.0.17-kai.1: $LIBFX_VERSION" >&2
  exit 1
fi
if [ -n "$(git -C "$root" status --porcelain --untracked-files=no)" ]; then
  echo "the checkout has uncommitted changes; package from a clean commit" >&2
  exit 1
fi
base_version=$(grep 'pub const version' "$root/src/main.zig" | head -1 | sed 's/.*"\(.*\)".*/\1/')

mkdir -p "$out"
out=$(cd "$out" && pwd)
rm -rf "$out/cli"
mkdir -p "$out/cli"
: > "$out/cli/fx.sha256"
for pair in "x64 x86_64" "arm64 aarch64"; do
  read -r cpu arch <<< "$pair"
  binary="$bins/fx-$arch"
  [ -f "$binary" ] || { echo "$binary is missing" >&2; exit 1; }
  # A static executable for the right machine, or the image can't run it.
  description=$(file -b "$binary")
  case "$arch" in x86_64) want="x86-64" ;; aarch64) want="ARM aarch64" ;; esac
  [[ "$description" == *"$want"* && "$description" == *"statically linked"* ]] || {
    echo "$binary is not a static $arch executable: $description" >&2; exit 1; }
  package="$scope/$name-cli-linux-$cpu"
  dir="$out/cli/$name-cli-linux-$cpu"
  mkdir -p "$dir/bin"
  install -m 0755 "$binary" "$dir/bin/fx"
  cp "$root/LICENSE" "$root/THIRD_PARTY_NOTICES.md" "$dir/"
  digest=$(sha256sum "$dir/bin/fx" | cut -d' ' -f1)
  printf '%s  bin/fx\n' "$digest" > "$dir/fx.sha256"
  printf '# %s\n\nThe Kai runtime'"'"'s fx command (fx %s with the Kai runtime'"'"'s changes) for Linux %s, built from %s. Its SHA-256 is in fx.sha256.\n' \
    "$package" "$base_version" "$cpu" "$commit" > "$dir/README.md"
  jq -n --arg name "$package" --arg version "$LIBFX_VERSION" --arg cpu "$cpu" --arg registry "$registry" --arg commit "$commit" '{
    name: $name, version: $version,
    description: "The Kai runtime'"'"'s fx command for Linux \($cpu)",
    os: ["linux"], cpu: [$cpu], files: ["bin/fx", "fx.sha256", "LICENSE", "THIRD_PARTY_NOTICES.md"],
    repository: { type: "git", url: "git+https://github.com/adeyemiadekunle/kai-runtime.git" },
    publishConfig: { registry: $registry }, license: "Apache-2.0", gitHead: $commit
  }' > "$dir/package.json"
  npm pack "$dir" --ignore-scripts --pack-destination "$out/cli" --json > "$dir.pack.json"
  files=$(jq -r '[.[0].files[].path] | sort | join(",")' "$dir.pack.json")
  [ "$files" = "LICENSE,README.md,THIRD_PARTY_NOTICES.md,bin/fx,fx.sha256,package.json" ] || { echo "$package has $files" >&2; exit 1; }
  printf '%s  %s\n' "$digest" "$package" >> "$out/cli/fx.sha256"
done
license=$(jq -r .license "$root/sdk/package.json")
[ "$license" = "Apache-2.0" ] || { echo "update the license in this script: sdk/package.json says $license" >&2; exit 1; }

# This machine's binary runs and reports the version it was built as.
case "$(uname -m)" in x86_64) cpu=x64 ;; aarch64) cpu=arm64 ;; *) cpu= ;; esac
if [ -n "$cpu" ]; then
  reported=$("$out/cli/$name-cli-linux-$cpu/bin/fx" --version)
  [[ "$reported" == *"$base_version"* ]] || { echo "fx --version said $reported" >&2; exit 1; }
  echo "fx runs: $reported"
fi
cat "$out/cli/fx.sha256"

[ "$publish" = "--publish" ] || exit 0
: "${NODE_AUTH_TOKEN:?set NODE_AUTH_TOKEN to publish}"
host=${registry#https://}
npmrc=$(mktemp)
trap 'rm -f "$npmrc"' EXIT
# shellcheck disable=SC2016 # npm reads the token from the environment itself
printf '%s:registry=%s\n//%s/:_authToken=${NODE_AUTH_TOKEN}\n' "$scope" "$registry" "${host%/}" > "$npmrc"
for archive in "$out"/cli/*.tgz; do
  package=$(tar -xzOf "$archive" package/package.json | jq -r .name)
  if npm view "$package@$LIBFX_VERSION" version --userconfig "$npmrc" > /dev/null 2>&1; then
    registry_dir=$(mktemp -d)
    got=$(npm pack "$package@$LIBFX_VERSION" --ignore-scripts --userconfig "$npmrc" --pack-destination "$registry_dir" --json | jq -r '.[0].filename')
    cmp "$archive" "$registry_dir/$got" || { echo "$package@$LIBFX_VERSION is already published with other contents" >&2; exit 1; }
    echo "$package@$LIBFX_VERSION is already published, unchanged"
    continue
  fi
  npm publish "$archive" --ignore-scripts --userconfig "$npmrc"
  echo "published $package@$LIBFX_VERSION"
done
