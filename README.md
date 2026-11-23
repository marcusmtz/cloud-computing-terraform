# NORCOM Infrastructure as Code

Public-safe source snapshot of the NORCOM academic multicloud project. It keeps the AWS, Azure and OCI Terraform roots while omitting local states, credentials, cloud account identifiers, generated application bundles and private variable files. This is evidence of the infrastructure definitions; it is not a copy of provider state and must not be applied to existing resources without importing and reviewing their state.

## Layout

- `aws/u2-core`: catalog and ERP API, RDS, IAM, monitoring, recovery, Windows AD and egress proxy definitions.
- `aws/mailcow`: Roundcube/Postfix/Dovecot demonstration host.
- `aws/network`, `aws/u2-budget`, `aws/u2-*`: network and academic activity roots.
- `aws/v1`: earlier catalog architecture retained for project history.
- `azure/u2-web`: portal and internal web application resources.
- `oci/backup`: private Object Storage backup bucket definition.
- `oci/mailcow`: OCI alternative retained as a design root.

These are independent Terraform roots; do not apply every directory together. The live project has separate state per root. This repository intentionally contains no live state.

## Safe use

Install Terraform and the provider CLIs, authenticate with your own AWS/Azure/OCI accounts, and select the intended account before planning. AWS roots use an explicit `expected_aws_account_id` guard; set `TF_VAR_expected_aws_account_id` to your own 12-digit account ID. AWS credentials come from the standard provider chain or `AWS_PROFILE`; no local profile name is embedded. Azure uses the active Azure CLI subscription unless `azure_subscription_id` is supplied. OCI uses the local OCI CLI profile.

Start with one root and inspect the complete plan:

```powershell
Set-Location .\aws\u2-core
terraform init
$env:TF_VAR_expected_aws_account_id = "123456789012" # replace with your account ID
terraform plan
```

Before any `apply`, replace all example domains and globally unique resource names, provide required inputs locally, and check costs and destructive actions. Keep those local values in ignored `*.tfvars` files or environment variables. Never commit Terraform state, plan files, secrets, credentials, or provider configuration files.

## Application packages

Generated Lambda ZIPs from the private application build are intentionally omitted because the compiled bundles contain demo contact data. The Terraform roots expect corresponding files under `api/dist/`; build and review those packages from the application source before planning or applying these roots. The small `aws/u2-lambda-web/web.zip` is a standalone reviewed demonstration package and is included.

## Scope

The copy preserves Terraform source and module documentation while removing local deployment state and account-specific values. It does not include the local multicloud orchestration scripts, provider credentials, DNS credentials, or the live resources themselves. See the original project's closeout report for implementation evidence; this public copy should not be treated as proof of current live state.
