# Security notes

- Terraform state can contain passwords, client secrets, provider-generated publishing credentials and infrastructure identifiers, even when Terraform marks an output as sensitive.
- This public copy excludes `*.tfstate*`, `*.tfvars` (except examples), plans, `.secure-state`, provider caches, local credentials, and generated API bundles.
- Review every file before publishing. Do not add account IDs, subscription IDs, email addresses, private keys, access tokens, passwords, or real customer data.
- If a secret was committed or shared, remove it from repository history and rotate/revoke it at the provider. Deleting the latest file alone does not remove it from Git history.
