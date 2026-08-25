# MongoDB Backup/Restore Runbook

- Take logical backups with `mongodump` (small/medium datasets).
- Use filesystem snapshots for large replica sets.
- Validate PITR/oplog window for recovery objectives.
- Restore test weekly with `mongorestore` and checksum validation.
