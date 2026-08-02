# infra-aws

Terraform for the platform AWS account. **Nothing here has been applied.**

Region `us-east-1`. Every configuration sets `allowed_account_ids`, so an apply
against the wrong account fails immediately rather than half-succeeding.

## Account topology

One workload account, one cluster, environments as namespaces.

| Account | Role | What runs there |
|---|---|---|
| `808540602855` (Dev) | **workload** | Everything: state backend, IAM/OIDC, VPC, the cluster |
| `909783398044` | **management only** | Organizations, Identity Center, budgets and the freeze SCP |

The split is not bureaucracy. **SCPs have no effect on the management account**,
so anything built there cannot be protected by the budget freeze. Keeping
workloads in a member account is what makes the cost ceiling enforceable.

`972379852819` (Staging) and `829860303036` (Prod) stay dormant and cost nothing.

Reach the workload account from management with:

```bash
aws sts assume-role \
  --role-arn arn:aws:iam::808540602855:role/OrganizationAccountAccessRole \
  --role-session-name platform
```

## Layout

| Directory | Owner | Contents |
|---|---|---|
| `bootstrap/` | `@cto` | *(workload account)* | State backend, KMS, budget, cost anomaly detection, CloudTrail, account baseline |
| `iam/` | `@security` | GitHub OIDC provider and the plan / apply roles |
| `network/` | `@infra` | VPC, subnets, NAT, endpoints, Route 53 — *not written yet, Wave 1 epic* |
| `eks/` | `@infra` | Cluster, node groups, Pod Identity — *not written yet, Wave 2 epic* |
| `ecr/` | `@infra` | Registries and lifecycle policies — *not written yet* |
| `bedrock/` | `@bedrock` | Model access, guardrails, VPC endpoints — *not written yet, Wave 7 epic* |

## First apply: the two-phase bootstrap

`bootstrap/` creates the bucket that stores everyone else's state, so it cannot
start with a remote backend. Run it locally once, then move its own state into
the bucket it just made.

```bash
cd bootstrap
cp terraform.tfvars.example terraform.tfvars   # gitignored; fill in alert_emails
terraform init
terraform plan          # read this properly - it creates the guardrails
terraform apply
```

Then migrate its state into the new bucket:

```bash
terraform output backend_config     # prints the block to paste
# add the printed backend "s3" block to bootstrap/main.tf, then:
terraform init -migrate-state
```

Every other configuration starts remote from the beginning:

```bash
cd ../iam
cp terraform.tfvars.example terraform.tfvars   # fill in from bootstrap outputs
terraform init \
  -backend-config="bucket=u25c-tfstate-909783398044" \
  -backend-config="key=shared/iam/terraform.tfstate" \
  -backend-config="region=us-east-1" \
  -backend-config="use_lockfile=true" \
  -backend-config="encrypt=true"
terraform plan
```

## What bootstrap creates

Guardrails come up in the same apply as the state backend, so there is no window
where the account can spend without a budget watching it.

- **State** — versioned, KMS-encrypted S3 bucket with TLS-only policy, `prevent_destroy`, and 90-day noncurrent version expiry. Locking is native S3 (`use_lockfile`); no DynamoDB table needed on Terraform ≥ 1.10.
- **Cost** — monthly budget with alerts at 50%, 80%, 100% actual and 100% *forecast*, plus daily cost anomaly detection. The forecast alert is the one that gives you time to react.
- **Audit** — multi-region CloudTrail with log file validation, KMS-encrypted.
- **Baseline** — account-level S3 public access block, EBS encryption by default, IAM password policy.

Default budget is **$200/month**, deliberately low while nothing is deployed.
`monthly_budget_usd` before applying if that is not your ceiling.

## What iam creates

Two roles with deliberately asymmetric trust:

| Role | Assumable from | Permissions |
|---|---|---|
| `u25c-shared-gha-plan` | pull requests in any of 7 infra repos | `ReadOnlyAccess` + state lock write |
| `u25c-shared-gha-apply` | **only** `refs/heads/main` of `infra-aws`, or the `aws-apply` environment | `AdministratorAccess` minus guardrail-removal and long-lived-credential actions |

A pull request can render a plan; it cannot change the account. The apply role is
explicitly denied `cloudtrail:StopLogging`, `s3:DeleteBucket`,
`kms:ScheduleKeyDeletion`, `iam:CreateAccessKey` and similar — CI has no
legitimate reason to remove the safety rails or mint static credentials.

## Conventions

Naming, tagging and state-key conventions are in
[`ops-program/CONVENTIONS.md`](https://github.com/Ubuntu-25c-market-prep/ops-program/blob/main/CONVENTIONS.md).

**This repository is public.** Never commit `terraform.tfvars`, state files, or
kubeconfigs — the security workflow blocks them at pull-request time and GitHub
push protection blocks credential patterns at push time.

## budgets/ — cost ceiling with an enforcement action

**AWS has no true hard spending cap.** This is the closest available:

| Layer | What it does |
|---|---|
| Alerts at 25 / 50 / 80 / 100% actual, 100% forecast | Email. With nothing deployed, the 25% notice is the real signal. |
| Per-account budgets (Dev / Staging / Prod) | Catches one account running away before the org total notices. |
| Cost anomaly detection, IMMEDIATE | Catches a spike inside a period the monthly budget would miss. |
| **Budget action → freeze SCP** | Attaches a deny policy to workload accounts, blocking new EC2, EKS, RDS, ELB, NAT, CloudFront and similar. |

Limits of the freeze, stated plainly:

- It blocks **new** resource creation. Anything already running keeps billing.
- **SCPs do not apply to the management account** (`909783398044`), so build the
  platform in Dev / Staging / Prod — not in management.
- `AUTOMATIC` approval trips without asking. Switch to `MANUAL` if a false
  positive locking the team out mid-sprint is worse than an overnight overrun.

### Prerequisite

SCPs are not currently enabled on this organisation (`PolicyTypes: []`).
Enabling the policy type changes nothing on its own — no policy is attached
until the budget action fires:

```bash
aws organizations enable-policy-type \
  --root-id r-e8kk \
  --policy-type SERVICE_CONTROL_POLICY
```

### Lifting a freeze

`terraform output detach_freeze_command` prints the exact detach command. Fix
the cause first, or it re-attaches at the next evaluation.
