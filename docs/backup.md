# Disaster Recovery Backup

All cluster data (Kubernetes resources + PVC contents) is backed up daily to S3 via
Velero, using Kopia for client-side encrypted, incremental file-system backups.
Backups are kept for 3 days, then transitioned to S3 Glacier Deep Archive after 1 day
for long-term, low-cost retention. This is a DR-only path: normal operations run
entirely on-cluster, and retrieval from Glacier Deep Archive takes up to 12 hours.

## Manual steps required

These steps can't be expressed in GitOps because they either produce secrets that
must not be committed, or they configure a third-party AWS account that this repo
doesn't own.

### 1. AWS IAM user

Create an IAM user (e.g. `evoteum-lab-backup`) with an inline policy scoped to the
backup bucket only. The bucket name is `evoteum-lab-backup-302ca542646a4546` (see
[`platform/backup/s3/bucket.yaml`](../platform/backup/s3/bucket.yaml)).

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:PutObject",
        "s3:DeleteObject",
        "s3:ListBucket",
        "s3:GetBucketLocation"
      ],
      "Resource": [
        "arn:aws:s3:::evoteum-lab-backup-302ca542646a4546",
        "arn:aws:s3:::evoteum-lab-backup-302ca542646a4546/*"
      ]
    }
  ]
}
```

Generate an access key for this user.

### 2. OpenBao secrets

Once OpenBao is [initialised](../README.md#openbao-initialisation), populate:

| Path                | Key                 | Value                                 |
|---------------------|---------------------|---------------------------------------|
| `secret/aws/backup` | `access_key_id`     | IAM access key ID from step 1         |
| `secret/aws/backup` | `secret_access_key` | IAM secret access key from step 1     |
| `secret/aws/backup` | `account_id`        | Your AWS account number (kept secret) |
| `secret/velero`     | `kopia_passphrase`  | A long random passphrase              |

The `account_id` isn't otherwise consumed by this repo's IaC — it's stored
purely for your own reference. The `kopia_passphrase` is the client-side
encryption key for all backup data: **if it's lost, backups in S3 become
permanently unrecoverable**. Store a copy outside of OpenBao too (password
manager, printed copy).

### 3. OpenBao Kubernetes auth method

External Secrets Operator authenticates to OpenBao using the Kubernetes auth method,
which has to be enabled and configured once (this is bootstrap, in the same vein as
OpenBao's own initialisation):

```bash
bao auth enable kubernetes

bao write auth/kubernetes/config \
  kubernetes_host="https://kubernetes.default.svc"

bao policy write external-secrets - <<EOF
path "secret/data/aws/backup" {
  capabilities = ["read"]
}
path "secret/data/velero" {
  capabilities = ["read"]
}
EOF

bao write auth/kubernetes/role/external-secrets \
  bound_service_account_names=external-secrets \
  bound_service_account_namespaces=external-secrets \
  policies=external-secrets \
  ttl=1h
```

After this, [`ClusterSecretStore/openbao`][secretstore] will be able to sync
the secrets above into the cluster, and everything downstream (Crossplane's
AWS ProviderConfig, the S3 bucket, Velero) is managed declaratively.

[secretstore]: ../platform/control-plane/external-secrets/clustersecretstore-openbao.yaml

## Restore

Restores are performed imperatively with the Velero CLI — this is expected; restore
is a deliberate, operator-triggered action, not something that should run via GitOps.

```bash
velero backup get
velero restore create --from-backup <backup-name>
```

Data in S3 Glacier Deep Archive needs to be restored to S3 Standard before Velero can
read it (`aws s3api restore-object`), which can take up to 12 hours.
