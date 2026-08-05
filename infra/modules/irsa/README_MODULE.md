# irsa module

This module is the AWS translation of GKE's "Workload Identity" concept —
IRSA (IAM Roles for Service Accounts).

The GCP pattern was:
    google_service_account_iam_member { member = "serviceAccount:PROJECT.svc.id.goog[namespace/ksa-name]" }

The AWS pattern is:
    trust policy condition: "oidc-provider:sub" == "system:serviceaccount:namespace:ksa-name"

For each role, we build a helper trust-policy data source that matches a
specific namespace + ServiceAccount name — no other pod can assume that
role, exactly the same namespace/SA-scoping that GKE Workload Identity uses.
