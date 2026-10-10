# backend-config

`terraform apply` in `bootstrap/` writes one partial S3 backend configuration
per account and Region here:

```
backend-config/<account_id>-<region>.s3.tfbackend
```

```hcl
bucket              = "acs-tfstate-<account_id>-<region>"
region              = "<region>"
kms_key_id          = "arn:aws:kms:<region>:<account_id>:key/<key-id>"
allowed_account_ids = ["<account_id>"]
```

Each remote-state root module supplies its own `key` in `backend.tf`. At init,
Terraform combines that key with this file's bucket, Region, KMS key, and
account guard:

```bash
terraform -chdir=account-baseline     init -backend-config=../backend-config/<account_id>-<region>.s3.tfbackend
terraform -chdir=environments/dev     init -backend-config=../../backend-config/<account_id>-<region>.s3.tfbackend
```

These files contain locations only, never credentials. They are safe to
commit, and committing them makes `init` reproducible. `allowed_account_ids`
makes the backend refuse to read or write state if your credentials belong
to a different account.
