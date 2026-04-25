# stowage-minio

Automated, reproducible builds of [MinIO](https://github.com/minio/minio) for
every architecture upstream supports. A scheduled GitHub Actions workflow
watches the upstream repository for new release tags; when a tag appears that
we have not yet built, it is built, signed (sha256), and published as a release
in this repository together with the unmodified upstream source — as required
by the AGPL.

## What gets built

For every new upstream tag, one binary is produced for each platform below.
The Linux set mirrors upstream's official multi-arch Docker image manifest;
Windows is included for native installs on Windows hosts.

| OS      | Architectures                  |
| ------- | ------------------------------ |
| linux   | amd64, arm64, ppc64le, s390x   |
| windows | amd64                          |

The Linux entries are exactly the platforms `docker pull minio/minio`
resolves to, so each maps 1:1 to a `linux/<arch>` Docker target. To extend
coverage (e.g. `linux/arm`, `linux/riscv64`, darwin), add entries to the
`matrix.target` list in `.github/workflows/build-release.yml`.

Each release contains:

- `minio-<os>-<arch>` (or `minio-windows-amd64.exe`) — the binary
- `SHA256SUMS` — checksums for every binary
- `minio-source.tar.gz` — pristine upstream source at the exact tag
  (this is what AGPL §6 requires us to publish alongside the binaries)
- `LICENSE` — the upstream AGPL v3 license text
- `NOTICE` — provenance: upstream commit SHA, build flags, Go version

## How it works

```
            ┌─────────────────────────┐    every hour
            │ check-upstream.yml      │◀──── (cron)
            │  • GET latest tag       │
            │  • compare to our tags  │
            └────────────┬────────────┘
                         │ new tag
                         ▼
            ┌─────────────────────────┐
            │ build-release.yml       │
            │  • matrix: 15 targets   │
            │  • CGO_ENABLED=0        │
            │  • -trimpath -tags kqueue
            │  • ldflags from upstream│
            └────────────┬────────────┘
                         │ artifacts
                         ▼
            ┌─────────────────────────┐
            │ publish job             │
            │  • SHA256SUMS           │
            │  • source tarball       │
            │  • LICENSE + NOTICE     │
            │  • gh release create    │
            └─────────────────────────┘
```

The check workflow runs on a cron and on `workflow_dispatch`. It uses the
GitHub API to read the latest upstream release tag and compares it against the
list of releases we have already published in this repository. If the tag is
new, it dispatches `build-release.yml` with that tag. Idempotent: re-running
when nothing has changed is a no-op.

## Stable download URLs

Each release is published with `--latest=true`, so GitHub's
`/releases/latest/download/<asset>` redirect always resolves to the
most-recent build. These URLs are stable — bookmark or hard-code them in
other workflows:

```
https://github.com/stowage-dev/stowage-minio/releases/latest/download/minio-linux-amd64
https://github.com/stowage-dev/stowage-minio/releases/latest/download/minio-linux-arm64
https://github.com/stowage-dev/stowage-minio/releases/latest/download/minio-linux-ppc64le
https://github.com/stowage-dev/stowage-minio/releases/latest/download/minio-linux-s390x
https://github.com/stowage-dev/stowage-minio/releases/latest/download/minio-windows-amd64.exe
https://github.com/stowage-dev/stowage-minio/releases/latest/download/SHA256SUMS
https://github.com/stowage-dev/stowage-minio/releases/latest/download/LICENSE
https://github.com/stowage-dev/stowage-minio/releases/latest/download/NOTICE
https://github.com/stowage-dev/stowage-minio/releases/latest/download/minio-source.tar.gz
```

(For a specific tag, swap `latest/download` for `download/<tag>`.)

### Consuming from another GitHub Actions workflow

```yaml
- name: Install MinIO (verified)
  run: |
    set -euo pipefail
    base=https://github.com/stowage-dev/stowage-minio/releases/latest/download
    curl -fsSL -o minio        "${base}/minio-linux-amd64"
    curl -fsSL -o SHA256SUMS   "${base}/SHA256SUMS"
    grep ' minio-linux-amd64$' SHA256SUMS | sha256sum -c -
    chmod +x minio
    sudo mv minio /usr/local/bin/minio
```

The `sha256sum -c -` step is what makes this safe across the redirect: even
though the download URL is mutable, every release pins the binaries' digests
in `SHA256SUMS`, so a tampered or stale binary is rejected.

## License compliance (AGPL v3)

MinIO is licensed under the [GNU AGPL v3](https://www.gnu.org/licenses/agpl-3.0.html).
We do not modify the source — we compile it as published — but redistributing
the resulting binaries still imposes obligations on us:

1. **Pass through the license.** Every release ships the upstream `LICENSE`
   file, unmodified.
2. **Provide Corresponding Source.** GPL §6(d) (incorporated by AGPL) lets us
   satisfy this by "offering equivalent access to the Corresponding Source in
   the same way through the same place at no further charge". Each release
   therefore includes `minio-source.tar.gz` — a pristine `git archive`
   of the upstream tag.
3. **Document provenance.** `NOTICE` records the upstream commit SHA, the Go
   toolchain version, and the build flags so anyone can verify or reproduce
   the build.
4. **No additional restrictions.** We add no DRM, no telemetry, no patches.

The build scripts and workflows in *this* repository (everything outside the
release tarballs) are licensed under the MIT license; see `LICENSE-BUILD`. The
binaries we publish remain under AGPL v3.

## Reproducing a build locally

```sh
# Build linux/amd64 for tag RELEASE.2025-01-01T00-00-00Z
./scripts/build.sh RELEASE.2025-01-01T00-00-00Z linux amd64
```

The script clones the upstream repo at the requested tag and runs the same
commands the CI does. Because we use `-trimpath`, `CGO_ENABLED=0`, and the
upstream-generated ldflags, builds are byte-for-byte reproducible given the
same Go toolchain version (recorded in `NOTICE`).

## Setup

To enable the automation in a fork:

1. Fork or push this repo to GitHub.
2. In **Settings → Actions → General**, allow "Read and write permissions" for
   the workflow `GITHUB_TOKEN` (needed to create releases).
3. Enable Actions. The first scheduled run (or a manual `workflow_dispatch` on
   `check-upstream.yml`) will pick up the latest upstream tag and start
   building.

No external secrets are required.
