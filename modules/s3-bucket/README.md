# s3-bucket

A private, encrypted, versioned S3 bucket. Nothing else.

**Owner:** `@infra`

## What is not configurable, and why

Five things are hardcoded in `main.tf` and are not inputs:

| Locked | Effect |
|---|---|
| `aws_s3_bucket_public_access_block` | all four flags `true` |
| `aws_s3_bucket_ownership_controls` | `BucketOwnerEnforced` — ACLs disabled |
| `aws_s3_bucket_server_side_encryption_configuration` | `aws:kms` with `bucket_key_enabled` |
| `aws_s3_bucket_versioning` | `Enabled` |
| `aws_s3_bucket_policy` | `DenyInsecureTransport` on bucket and objects |

This is not caution for its own sake. A variable that can make a bucket public
turns "is this bucket private?" into a question with a per-caller answer, checked
by whoever happens to read that pull request. Hardcoded, it has one answer for
every caller, and changing it means editing this file — which CODEOWNERS routes
to `@infra`.

**Need a genuinely public bucket** — a CloudFront origin, a static site? Do not
add a switch here. Write a second module whose name says what it does.

## Inputs

| Name | Type | Default | Description |
|---|---|---|---|
| `name` | string | — | Bucket name. **Globally unique across every AWS account** — suffix the account id. |
| `kms_key_arn` | string | — | Encryption key. `bootstrap` output `kms_key_arn`. |
| `log_bucket` | string | `""` | Server access log target. `""` disables logging. |
| `log_prefix` | string | `""` | Key prefix for delivered logs. |
| `noncurrent_expiration_days` | number | `90` | Noncurrent versions deleted after this many days. |
| `expiration_days` | number | `null` | Current versions expire after this many days. `null` = never. |
| `abort_incomplete_multipart_days` | number | `7` | Abort orphaned multipart uploads. |
| `force_destroy` | bool | `false` | Permit deleting a non-empty bucket. |
| `tags` | map(string) | `{}` | Merged onto the bucket, on top of provider `default_tags`. |

Versioning is always on, which is why `noncurrent_expiration_days` matters: without
it every overwrite is retained and billed forever.

## Outputs

| Name | Description |
|---|---|
| `id` | Bucket name. |
| `arn` | Bucket ARN, for IAM policy `Resource` blocks. |
| `bucket_regional_domain_name` | Regional endpoint; avoids the global domain's post-creation redirect. |

## Example

```hcl
module "app_data" {
  source = "../modules/s3-bucket"

  name        = "u25c-shared-app-data-808540602855"
  kms_key_arn = var.kms_key_arn
  log_bucket  = "u25c-s3-access-logs-808540602855"
  log_prefix  = "app-data/"
}
```

A runnable version is in [`examples/basic`](examples/basic).

## Tests

`tests/defaults.tftest.hcl` asserts the locked posture above. Plan-mode only —
no AWS calls, no credentials, no cost:

```bash
terraform -chdir=modules/s3-bucket init
terraform -chdir=modules/s3-bucket test
```

Run it after any change to `main.tf`. The tests are what stop the table at the
top of this file from decaying into a comment that used to be true.

## Note on the SCP

`organization/policies.tf` denies `s3:DeleteBucket`, `s3:DeleteBucketPolicy` and
`s3:PutBucketPublicAccessBlock` on buckets matching `u25c-tfstate-*`,
`u25c-cloudtrail-*` and `u25c-s3-access-logs-*`.

**Do not name a new bucket into one of those patterns.** The deny on
`s3:PutBucketPublicAccessBlock` applies at *create* time, so this module cannot
provision a bucket whose name matches — the public access block is denied and the
apply fails. If a bucket should be protected, create it first and add the name to
`protected_buckets` in a second pull request.
