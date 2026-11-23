# Mail web demo with Roundcube, Postfix and Dovecot

This Terraform root describes a small AWS email demonstration: one Ubuntu EC2 instance runs Roundcube, Postfix and Dovecot. Mailbox credentials are generated randomly at first boot; no password is committed in this repository. Retrieve demo credentials only through the instance's authorized administration channel and never paste them into GitHub.

Before using this root, provide your own AWS account ID, an owned mail domain, DNS records, a valid contact email, and an AWS credential profile. The sample uses `example.invalid` intentionally and will not issue a public certificate until replaced with a real domain. Review inbound mail-port restrictions and provider quotas for your account.

Run Terraform only from this module directory. Initialize, inspect `terraform plan`, and apply only after confirming the account, region, DNS, and expected cost. State files and variable files are intentionally excluded from this public copy.
