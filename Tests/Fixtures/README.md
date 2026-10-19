# Test fixtures

All test and verification files live under this folder. Nothing outside the repository is ever used as a fixture.

- `Generated/`: created and deleted by `swift test` (see `OrganizerCoreTests/FixtureSupport.swift`, which refuses any other path). Git-ignored.
- `Manual/`: created by `scripts/make_manual_fixture.sh` for the manual checklist. Git-ignored.
- `Snapshots/`: before/after snapshots written by `scripts/snapshot_fixture.sh`, kept outside the scanned folder. Git-ignored.
