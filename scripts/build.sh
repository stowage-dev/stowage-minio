#!/usr/bin/env bash
#
# build.sh — reproduce one MinIO binary locally, exactly the way CI does.
#
# Usage:
#   scripts/build.sh <upstream-tag> <goos> <goarch> [output-dir]
#
# Example:
#   scripts/build.sh RELEASE.2025-01-01T00-00-00Z linux amd64 ./out
#
# The resulting binary is bit-identical to the one published in the
# corresponding GitHub release, given the same Go toolchain version.

set -euo pipefail

if [[ $# -lt 3 ]]; then
  echo "usage: $0 <upstream-tag> <goos> <goarch> [output-dir]" >&2
  exit 2
fi

TAG="$1"
GOOS="$2"
GOARCH="$3"
OUT_DIR="${4:-./out}"

mkdir -p "${OUT_DIR}"
OUT_DIR="$(cd "${OUT_DIR}" && pwd)"

work=$(mktemp -d)
trap 'rm -rf "${work}"' EXIT

echo "==> Cloning minio/minio at ${TAG} into ${work}"
git clone --depth 1 --branch "${TAG}" https://github.com/minio/minio "${work}/minio"
# gen-ldflags.go calls `git describe --tags`, which needs the tag visible.
git -C "${work}/minio" fetch --tags --depth 1 origin "+refs/tags/${TAG}:refs/tags/${TAG}" 2>/dev/null || true

cd "${work}/minio"

echo "==> Generating ldflags"
ldflags=$(go run buildscripts/gen-ldflags.go)

ext=""
if [[ "${GOOS}" == "windows" ]]; then ext=".exe"; fi
out="${OUT_DIR}/minio-${GOOS}-${GOARCH}${ext}"

echo "==> Building ${out}"
CGO_ENABLED=0 GOOS="${GOOS}" GOARCH="${GOARCH}" \
  go build -tags kqueue -trimpath \
    --ldflags "${ldflags}" \
    -o "${out}" \
    ./

echo "==> Done"
( cd "${OUT_DIR}" && sha256sum "$(basename "${out}")" )
