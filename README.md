# infra-aws

Terraform for the platform AWS organisation. Layers 0–3 are applied; see the
Layout table for what is live and what is still a directory that does not exist.

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

### Organisational units

```
Root r-e8kk
├── u25c-workloads   → Dev            ← guardrail SCP + tag policy
├── u25c-dormant     → Staging, Prod  ← deny-all-but-inspection SCP
└── (root)           → management, and one SUSPENDED account that cannot be moved
```

Guardrails hang off the OUs, never off the root — the root would also cover the
management account, and the management account is the only place from which a
bad policy can be undone. See `docs/adr/0007` in `ops-program`.

### Reaching an account

Humans use IAM Identity Center. See **Access** below. The break-glass path, for
when Identity Center itself is the problem:

```bash
aws sts assume-role \
  --role-arn arn:aws:iam::808540602855:role/OrganizationAccountAccessRole \
  --role-session-name platform
```

Or, as a named profile — this is what the `terraform` commands below assume:

```ini
# ~/.aws/config
[profile u25c-dev]
role_arn       = arn:aws:iam::808540602855:role/OrganizationAccountAccessRole
source_profile = default
region         = us-east-1
```

## Access

Everyone signs in at one link with their **GitHub handle** as the username:

    https://ubuntu-25c.awsapps.com/start

Four roles, not fifteen. Which ones you see depends on your groups:

| Permission set | Who | Where | What |
|---|---|---|---|
| `u25c-PlatformAdmin` | `u25c-cto` | Dev + management | Administrator |
| `u25c-PlatformEngineer` | `u25c-engineers` | Dev | PowerUser + scoped IAM, under a permissions boundary |
| `u25c-ReadOnly` | `u25c-all` | Dev + management | Read everything, change nothing |
| `u25c-Billing` | `u25c-billing` | management | Budgets and Cost Explorer |

Least privilege comes from three layers, not from bespoke per-workstream
policies: the permission set says what you may attempt, the workloads-OU SCP
says what the account will allow anyone to do, and the permissions boundary
caps any role you create. The fifteen `u25c-ws-*` groups mirror the GitHub teams
and grant nothing yet — they are there so scoping later is a data change.

Onboarding a person, including how one-time passwords are handed out, is
[`ops-program/runbooks/onboard-to-aws.md`](https://github.com/Ubuntu-25c-market-prep/ops-program/blob/main/runbooks/onboard-to-aws.md).

## Layout

| Directory | Runs in | Owner | Contents | Status |
|---|---|---|---|---|
| `bootstrap/` | workload | `@cto` | State backend, KMS, access logs, CloudTrail, account baseline | applied |
| `budgets/` | **management** | `@cto` | Org ceiling, per-account budgets, anomaly detection, freeze SCP | applied |
| `organization/` | **management** | `@security` | OUs, account placement, guardrail SCPs, tag policy | applied |
| `identity/` | **management** | `@security` | Identity Center groups, users, permission sets, assignments | applied |
| `iam/` | workload | `@security` | GitHub OIDC provider, plan / apply roles, engineer boundary | applied |
| `network/` | workload | `@infra` | VPC, subnets, NAT, endpoints, Route 53 — *not written yet, Wave 1 epic* | — |
| `eks/` | workload | `@infra` | Cluster, node groups, Pod Identity — *not written yet, Wave 2 epic* | — |
| `ecr/` | workload | `@infra` | Registries and lifecycle policies — *not written yet* | — |
| `bedrock/` | workload | `@bedrock` | Model access, guardrails, VPC endpoints — *not written yet, Wave 7 epic* | — |

Three configurations run in the management account, and they have to:
Organizations, SCPs, budget actions and Identity Center exist nowhere else.

**Apply order matters in one place:** `iam/` before `identity/`. The engineer
permission set attaches a permissions boundary that `iam/` creates in the
workload account.

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

Every other configuration starts remote from the beginning. The state bucket
lives in the **workload** account even for the management-account layers, which
is why `bootstrap` grants `state_reader_account_ids` on both the bucket policy
and the KMS key:

```bash
cd ../iam
cp terraform.tfvars.example terraform.tfvars   # fill in from bootstrap outputs
terraform init \
  -backend-config="bucket=u25c-tfstate-808540602855" \
  -backend-config="key=shared/iam/terraform.tfstate" \
  -backend-config="region=us-east-1" \
  -backend-config="use_lockfile=true" \
  -backend-config="encrypt=true" \
  -backend-config="kms_key_id=$(cd ../bootstrap && terraform output -raw kms_key_arn)"
terraform plan
```

State keys follow `<scope>/<component>/terraform.tfstate`. Management-account
layers use the `management/` scope: `management/budgets`,
`management/organization`, `management/identity`.

**Which credentials each layer needs.** Getting this wrong fails fast, because
of `allowed_account_ids`, with `AWS account ID not allowed`:

| Layer | Credentials |
|---|---|
| `bootstrap/`, `iam/` | workload — `AWS_PROFILE=u25c-dev` |
| `budgets/`, `organization/`, `identity/` | management — the default profile |

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

It also creates `u25c-engineer-boundary`, the permissions boundary consumed by
`identity/`. A boundary is an **intersection**, not a deny list: it allows `*`
and then subtracts, because a policy containing only `Deny` statements grants
nothing and would leave every engineer session with zero permissions. Its denies
mirror the workloads-OU SCP deliberately — the ceiling a person works under and
the ceiling a role they create works under should be the same ceiling, or the
difference between them is an escalation path.

## CI

`.github/workflows/terraform.yml` runs `fmt`, `validate` and `plan` on every
pull request touching `bootstrap/` or `iam/`, and applies on `main` through the
`aws-apply` environment. Set two repository variables from `iam` outputs:

```bash
gh variable set AWS_PLAN_ROLE_ARN  --body "$(terraform -chdir=iam output -raw plan_role_arn)"
gh variable set AWS_APPLY_ROLE_ARN --body "$(terraform -chdir=iam output -raw apply_role_arn)"
```

Because `terraform.tfvars` is gitignored and this repository is public, CI
reconstructs it on the runner from two **secrets** — not variables. GitHub prints
a step's `env` block into the workflow log, and the logs of a public repository
are public, so a variable would publish the account ids and alert addresses on
every run:

```bash
gh secret set TFVARS_BOOTSTRAP < bootstrap/terraform.tfvars
gh secret set TFVARS_IAM       < iam/terraform.tfvars
```

**CI covers the workload-account layers only.** Both OIDC roles live in
`808540602855`, so `budgets/`, `organization/` and `identity/` stay CTO-local
applies until someone adds an OIDC provider to the management account. That is a
deliberate gap: Organizations, SCPs and Identity Center are exactly where an
automatic apply from a merged pull request has the largest blast radius.

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

`SERVICE_CONTROL_POLICY` and `TAG_POLICY` are both enabled on root `r-e8kk`,
managed by `organization/`. Enabling a policy type changes nothing on its own —
the freeze policy stays unattached until the budget action fires. Confirm that
is still true with:

```bash
aws organizations list-targets-for-policy --policy-id p-d5aegejc   # expect empty
```

### Lifting a freeze

`terraform output detach_freeze_command` prints the exact detach command. Fix
the cause first, or it re-attaches at the next evaluation.

## organization/ — guardrails that apply to everyone

`u25c-org-guardrails`, attached to the workloads OU, denies: the account root
user, any region other than `us-east-1`, instance types outside a costed
allow-list, deleting or silencing CloudTrail, deleting the state and audit
buckets, and creating IAM users or access keys.

Two things to internalise before it surprises you:

- **It applies to you as well.** SCPs constrain every principal in the account,
  including `OrganizationAccountAccessRole` and `u25c-PlatformAdmin`. If a
  legitimate change is denied, the fix is to change the policy, not to look for
  a role that can bypass it — there isn't one.
- **The management account is the escape hatch.** SCPs never apply there. Any
  policy that locks the workload account can be detached from `909783398044`:

  ```bash
  terraform -chdir=organization output -raw detach_guardrails_command
  ```

  Re-attach by re-applying `organization/`, which will show the drift.

`u25c-org-dormant-freeze` on the dormant OU denies everything except inspection,
so Staging and Prod cannot accrue cost while ADR 0003 keeps them open.

The tag policy is **report-only** — no `enforced_for`. An enforcing tag policy
rejects resource creation, which turns one missing tag into a failed apply
halfway through a wave. Turn on enforcement once FinOps showback says the
account is already compliant.

## identity/ — who signs in

See **Access** above for the user-facing summary. Two implementation notes:

- `user_name` is immutable in the identity store. Changing it destroys the user
  and takes their password and registered MFA device with it, which is why
  accounts predating the handle convention keep their original sign-in name via
  `sign_in_name_overrides` rather than being renamed.
- Passwords cannot be set by Terraform, and AWS exposes no API for issuing a
  one-time password. That step is per-user in the console — see the onboarding
  runbook.
