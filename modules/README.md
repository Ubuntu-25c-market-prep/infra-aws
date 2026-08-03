# modules

Reusable Terraform modules consumed by the layers in this repository. Nothing
here is applied directly — modules are called, never run.

**Owner:** `@infra` · **Waves:** 1–2

Absorbed from the former `infra-modules` repository per
[ADR 0010](https://github.com/Ubuntu-25c-market-prep/ops-program/blob/main/docs/adr/0010-one-repository-per-delivery-boundary.md).

## Consuming a module

Relative path, from the layer that calls it:

```hcl
module "vpc" {
  source = "../modules/vpc"

  name       = "u25c-shared"
  cidr_block = "10.0.0.0/16"
  az_count   = 3
}
```

## Why there are no version tags

`infra-modules` versioned modules independently — `vpc/v1.2.0` — so a consumer
could stay on one version while another moved ahead. ADR 0010 supersedes that,
and the reasoning is worth keeping visible rather than buried in a decision
record:

Independent versioning pays for itself when there are **several consumers on
different release cadences**. There is one consumer — this repository — and the
programme has no second one planned. What the tag cycle bought in that situation
was a mandatory two-pull-request dance for every module change: one to release,
one to adopt. What it cost was that a module and its caller could never change
atomically, so a breaking change was only discovered at adoption time.

With a relative path both sides move in one reviewed commit, and `terraform plan`
in CI exercises the change against its real caller before merge.

**This is a reversible decision.** If a second consumer appears — a separate
account, a second region, another repository — extract `modules/` back out and
restore tag versioning. That is a normal repository split, and the module
contract below is written so nothing else has to change when it happens.

## Module contract

Modules never contain a `backend` block, a `provider` block, or a hardcoded
account id. Providers are passed in by the caller. This is what keeps a module
callable from any layer and extractable later without rewriting it.

## Layout

```
<module>/
├── main.tf
├── variables.tf     every input has description + type
├── outputs.tf       every output has description
├── versions.tf      required_version + required_providers, no backend
├── README.md        inputs, outputs, and a worked example
└── examples/
    └── basic/       a runnable example that plans cleanly
```

## Changing a module

1. Pull request against `main`, reviewed by `@infra`.
2. `examples/basic` must plan cleanly.
3. Update the module's README — inputs, outputs, example.
4. Callers change in the same pull request. CI plans every affected layer, so a
   change that would force resource replacement shows up in the plan output
   before anyone approves it.

Read the plan. A change that replaces a resource is still a breaking change even
though nothing in the interface moved — "applying this will not destroy your
database" is part of the contract, and without tags the plan is what enforces it.

## Standards

[Terraform Standards](https://github.com/Ubuntu-25c-market-prep/ops-program/blob/main/docs/terraform-standards.md) ·
[State Strategy](https://github.com/Ubuntu-25c-market-prep/ops-program/blob/main/docs/terraform-state-strategy.md)
