# Releasing

The `release.yml` workflow publishes version tags after the complete CI matrix passes. The tag must match `Hawk::VERSION` and belong to `main`.

RubyGems trusts the `svyatov/hawk.ruby` repository, the `release.yml` workflow, and the `release` environment. The environment permits `v*` tags.

The workflow builds the gem once, generates its checksum and GitHub provenance attestation, and stores the artifact for 14 days. Publishing downloads those exact bytes.

To cut a version:

1. Update the version, changelog, and installation example. Run the checks and merge to `main`.
2. Create an annotated version tag, for example `git tag -a v0.1.0 -m 'Release 0.1.0'`.
3. Push the tag with `git push origin v0.1.0` and monitor the Release workflow.

## Recover a partial publication

Use GitHub's failed-jobs rerun, for example `gh run rerun RUN_ID --failed --repo svyatov/hawk.ruby`. This preserves the successful build and its archived artifact.

If RubyGems already has the version, publication continues only when its SHA256 matches the archived gem. A mismatch or failed registry lookup stops the release.

GitHub releases start as drafts. A retry verifies the tag and commit, uploads missing assets, and publishes the draft. Existing assets must have matching checksums; they are never replaced.

Do not rebuild a published version or move its tag. If the archived artifact has expired, recover and verify the original published bytes before completing the GitHub release.
