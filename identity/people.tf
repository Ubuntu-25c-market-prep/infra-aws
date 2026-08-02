###############################################################################
# The roster.
#
# SOURCE OF TRUTH: ops-program/program/roster.yaml
#
# Duplicated here rather than read across repositories, because a Terraform
# configuration that cannot plan without cloning a second repo is a configuration
# nobody can run in CI. When roster.yaml changes, change this and say so in the
# pull request - the two are compared during onboarding review.
#
# `key` is the GitHub handle, and it is also the Identity Center sign-in name.
# One identifier across GitHub, the board and AWS is worth more than a prettier
# username.
###############################################################################

locals {
  workstreams = [
    "infra", "security", "scaling", "argocd", "flux", "monitoring", "logging",
    "tracing", "utils", "velero", "rancher", "finops", "istio", "zerotrust", "bedrock",
  ]

  people = {
    aslantishbek = { first = "Aslan", cto = true, workstreams = ["infra", "tracing", "bedrock"] }
    sevgiabaysal = { first = "Sevgi", cto = true, workstreams = ["tracing", "rancher", "istio"] }
    ElenaPinar   = { first = "Elena", cto = false, workstreams = ["infra", "argocd", "tracing"] }
    dianadi11    = { first = "Diana", cto = false, workstreams = ["infra", "flux", "tracing"] }

    katoteshiku1989       = { first = "Andrii P", cto = false, workstreams = ["security", "monitoring", "logging"] }
    romanhumeniuk312      = { first = "Roman", cto = false, workstreams = ["security", "monitoring", "logging"] }
    sergiidan             = { first = "Sergii", cto = false, workstreams = ["scaling", "zerotrust", "bedrock"] }
    bloomingirl           = { first = "Hanna", cto = false, workstreams = ["scaling", "argocd", "velero"] }
    Drdmytrush90          = { first = "Dmytro", cto = false, workstreams = ["scaling", "argocd", "utils"] }
    ZarinaSagynalieva     = { first = "Zarina", cto = false, workstreams = ["flux", "finops", "zerotrust"] }
    tatinatech            = { first = "Tatina", cto = false, workstreams = ["flux", "monitoring", "bedrock"] }
    Nikita-DS22           = { first = "Nikita", cto = false, workstreams = ["logging", "utils", "rancher"] }
    kadze                 = { first = "Andrii Sh", cto = false, workstreams = ["utils", "velero", "istio"] }
    cristianarseni        = { first = "Chris", cto = false, workstreams = ["security", "velero", "istio"] }
    Vera-Terna            = { first = "Vera", cto = false, workstreams = ["rancher", "finops"] }
    zhemaitite-anastasiia = { first = "Nastya", cto = false, workstreams = ["finops", "istio", "zerotrust"] }

    # In the GitHub org, not on the source roster. No workstream means no
    # engineer access - read-only until someone assigns one. This is the model
    # working, not an oversight to paper over.
    Bakmurat = { first = "Bakmurat", cto = false, workstreams = [] }
  }

  ###############################################################################
  # Derived membership
  ###############################################################################

  # Access groups decide what you can do. Workstream groups decide nothing yet -
  # see main.tf.
  access_group_members = {
    cto       = [for h, p in local.people : h if p.cto]
    engineers = [for h, p in local.people : h if length(p.workstreams) > 0]
    billing   = [for h, p in local.people : h if contains(p.workstreams, "finops")]
    all       = keys(local.people)
  }

  workstream_group_members = {
    for ws in local.workstreams :
    ws => [for h, p in local.people : h if contains(p.workstreams, ws)]
  }

  # Flattened to one resource instance per (group, person) pair.
  access_memberships = merge([
    for group, handles in local.access_group_members : {
      for h in handles : "${group}/${h}" => { group = group, handle = h }
    }
  ]...)

  workstream_memberships = merge([
    for ws, handles in local.workstream_group_members : {
      for h in handles : "${ws}/${h}" => { workstream = ws, handle = h }
    }
  ]...)
}
