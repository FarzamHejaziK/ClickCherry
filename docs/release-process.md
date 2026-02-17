# Release Process

## Versioning

- Tags follow `vMAJOR.MINOR.PATCH` (example: `v0.2.0`).
- Update `/CHANGELOG.md` before tagging.

## Branch and Review Requirements

- Merge into `main` only through reviewed PRs.
- Required checks: CI + DCO.
- Owner approval required before merge.

## Create a Release

1. Ensure `main` is green.
2. Update `CHANGELOG.md`.
3. Create and push a version tag:

```bash
git tag v0.1.1
git push origin v0.1.1
```

4. GitHub Actions `Release` workflow builds and publishes artifacts.

## Signed macOS Artifacts

Release workflow signs with Developer ID, submits notarization, staples the ticket,
and publishes the notarized app zip.

Expected secrets:

- `APPLE_DEVELOPER_ID_APPLICATION_CERT_BASE64`
- `APPLE_DEVELOPER_ID_APPLICATION_CERT_PASSWORD`
- `APPLE_TEAM_ID`
- `APPLE_ID`
- `APPLE_APP_SPECIFIC_PASSWORD`

If any required secret is missing, the release workflow fails fast.
