# setup-sorus

Installs the Sorus client on a GitHub Actions runner and puts `sorus` and
`cargo-sorus` on `PATH`.

```yaml
- uses: sorus-run/setup-sorus@v1
  with:
    version: 0.3.0
- run: cargo sorus test --locked
  env:
    SORUS_TOKEN: ${{ secrets.SORUS_TOKEN }}
```

Runners: Linux and macOS, x64 and ARM64. The action downloads the file for
the runner from the release `v<version>` of
[sorus-run/sorus](https://github.com/sorus-run/sorus/releases) and installs
it only when its SHA-256 matches the release's `SHA256SUMS` and, with
`verify-attestation: true` (the default), when `gh attestation verify`
accepts the release's signed provenance. GitHub-hosted runners carry `gh`.

| input | default | meaning |
| --- | --- | --- |
| `version` | `latest` | three numbers, such as `0.3.0`, or `latest` |
| `sha256` | none | the SHA-256 the runner's file must have, to pin the exact bytes |
| `verify-attestation` | `true` | `false` checks `SHA256SUMS` alone, for a runner without `gh` |

Outputs: `version`, the version installed, and `directory`, the directory
added to `PATH`.

The client's terms are in [LICENSE](LICENSE).
