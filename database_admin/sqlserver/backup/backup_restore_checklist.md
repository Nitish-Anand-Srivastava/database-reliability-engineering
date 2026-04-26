# SQL Server Backup/Restore Checklist

- Verify full/diff/log backup jobs succeeded in last 24h.
- Validate restore chain in lower environment weekly.
- Run `RESTORE VERIFYONLY` on latest full backup.
- Monitor backup duration growth and compression ratio.
- Confirm encryption keys/certificates are recoverable.
