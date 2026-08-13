# irsa module

This module creates IRSA (IAM Roles for Service Accounts) — the mechanism
that lets a specific Kubernetes ServiceAccount assume a specific, narrowly
scoped IAM Role, with no static AWS credential involved anywhere.

The trust policy pattern used throughout this module:

    condition: "oidc-provider:sub" == "system:serviceaccount:<namespace>:<sa-name>"

For each role, a dedicated trust-policy data source matches one specific
namespace + ServiceAccount name — no other pod in the cluster can assume
that role.
