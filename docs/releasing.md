# Releasing

The `release.yml` workflow publishes version tags after the complete CI matrix passes. The tag must match `Hawk::VERSION` and belong to `main`.

RubyGems trusts the `svyatov/hawk.ruby` repository, the `release.yml` workflow, and the `release` environment. The environment permits `v*` tags and requires approval from the maintainer before publication.

The workflow builds the gem once, inventories its packaged files and external runtime requirements in `sbom.cdx.json`, and stores the artifacts for 14 days. Tag-triggered checks install frozen dependencies without a Bundler cache. After approval, publishing signs and uploads the original gem with its provenance to RubyGems. The GitHub release contains the same gem, the inventory, and `SHA256SUMS`, with attestations covering the gem and inventory.

To cut a version:

1. Update the version, changelog, and installation example. Run the checks and merge to `main`.
2. Create a signed version tag, for example `git tag -s v0.1.2 -m 'Release 0.1.2'`.
3. Push the tag with `git push origin v0.1.2` and monitor the Release workflow.
4. Review the successful build and approve the `release` environment deployment.

To verify downloaded release assets, run `gh attestation verify hawk-ruby-0.1.2.gem --repo svyatov/hawk.ruby --signer-workflow svyatov/hawk.ruby/.github/workflows/release.yml`, then repeat for `sbom.cdx.json`. Run `sha256sum --check SHA256SUMS` from the download directory. RubyGems serves its gem attestation at `https://rubygems.org/api/v1/attestations/hawk-ruby-0.1.2.json`.

## Recover a partial publication

Use GitHub's failed-jobs rerun, for example `gh run rerun RUN_ID --failed --repo svyatov/hawk.ruby`. This preserves the successful build and its archived artifact.

If RubyGems already has the version, publication continues only when its SHA256 matches the archived gem. A mismatch or failed registry lookup stops the release.

GitHub releases start as drafts. A retry verifies the tag and commit, uploads missing assets, and publishes the draft. Existing assets must have matching checksums; they are never replaced.

Do not rebuild a published version or move its tag. If the archived artifact has expired, recover and verify the original published bytes before completing the GitHub release.
