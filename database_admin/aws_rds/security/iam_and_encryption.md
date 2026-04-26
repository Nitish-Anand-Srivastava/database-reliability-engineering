# AWS RDS Security Baseline

- Encryption at rest with KMS enabled.
- TLS enforced in-transit.
- IAM auth where supported.
- Least-privilege SG/NACL and no broad CIDR access.
- Automated credential rotation via Secrets Manager.
