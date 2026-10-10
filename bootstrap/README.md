# bootstrap

**Run this first, once per AWS account.** Bootstrap builds the secure place
where every other part of this project keeps its Terraform records.

## The simple version

Terraform is like a builder who keeps a **notebook**. Every time it builds
something in AWS, it writes it down. That notebook is called **state**.
Without it, Terraform forgets what it built.

We want every notebook kept in a safe locker in the cloud, so it can't get
lost and only the right people can read it. But the locker doesn't exist
yet, and a builder can't put its notebook inside a locker that hasn't been
built.

**Bootstrap builds the locker.** It creates:

1. **The locker:** an S3 bucket where the other notebooks (account
   baseline, dev, staging, prod) are stored.
2. **A lock for the locker:** a KMS key, so the notebooks are encrypted.
3. **A separate key for each worker:** one IAM role per part of the
   project. The dev role can only open the dev notebook, the prod role only
   the prod notebook, and so on.
4. **Directions to the locker:** a small file in `backend-config/` that
   tells the other parts where the locker is.

Bootstrap's **own** notebook can't go in the locker, because the locker
didn't exist when bootstrap started. So it stays on your computer as
`bootstrap/terraform.tfstate`. Keep a secret, encrypted copy of it somewhere
safe, like a spare house key.

## What it creates

| Resource | Name | Purpose |
|---|---|---|
| S3 bucket | `acs-tfstate-<account_id>-<region>` | Remote state for every other root. Versioned, KMS-encrypted, public access blocked, TLS required. |
| Bucket policy | (on the bucket) | Each root can read and write only its own `aws-cloud-security/<scope>/` prefix. Old state versions can't be deleted except by break-glass principals. |
| KMS key | `alias/acs-tfstate` | Encrypts state. Key rotation on, 30-day deletion window. |
| IAM roles | `acs-tf-account-baseline`, `acs-tf-dev`, `acs-tf-staging`, `acs-tf-prod` (path `/acs/terraform/`) | The only role allowed to deploy each root. Environment roles are explicitly denied any change to the account security baseline. |
| IAM policies | `acs-dev-workload-boundary`, `acs-staging-workload-boundary`, `acs-prod-workload-boundary` | Permissions boundaries every environment-created role must carry, so environments can't create admin roles. |
| Local file | `../backend-config/<account_id>-<region>.s3.tfbackend` | Bucket, Region, KMS key and allowed account ID for `terraform init`. No credentials. |

The bucket and KMS key have `prevent_destroy`, so a stray `terraform destroy`
can't delete them.

## How to run it

You need credentials for an administrator in the target account.

```bash
export TF_VAR_account_id=<12-digit account id>   # choose the account explicitly
cd bootstrap
terraform init
terraform plan -out=tfplan
terraform apply tfplan
terraform output
```

Then:

1. **Back up the state** (see below).
2. Set up AWS CLI profiles that assume the `acs-tf-*` roles, and deploy
   `account-baseline` next. See
   [§5 of the ownership doc](../docs/terraform-state-ownership.md#5-deployment-order).

Settings live in `terraform.tfvars`:

| Variable | Default | Notes |
|---|---|---|
| `aws_region` | `us-east-1` | Region of the state bucket. |
| `state_scopes` | `account-baseline`, `dev`, `staging`, `prod` | In a multi-account setup, list only the scopes this account hosts, e.g. `["account-baseline", "prod"]`. |
| `deployer_trusted_principal_arns` | `[]` (account root) | Restrict to your SSO or CI roles. |
| `require_mfa` | `true` | Set `false` when the trusted principals are SSO or CI roles; their sessions don't carry the MFA flag. |
| `break_glass_principal_arns` | `[]` | Principals exempt from per-scope isolation. Keep empty or tightly controlled. |

## Protecting the local state

* It is never committed (`.gitignore` excludes `*.tfstate`).
* After every apply, store an encrypted copy with your break-glass
  material, for example:
  `age -r <recipient> -o bootstrap-$(date +%F).tfstate.age terraform.tfstate`
* Keep the working copy `chmod 600` on an encrypted disk.
* If it's lost, every resource has a predictable name and can be brought
  back with `terraform import`.

Full details are in
[§6 of the ownership doc](../docs/terraform-state-ownership.md#6-protecting-the-bootstrap-state).

## Removing it

Bootstrap is removed **last**, only after every other root in the account
has been destroyed or moved elsewhere. The procedure is in
[§9.4 of the ownership doc](../docs/terraform-state-ownership.md#94-bootstrap-last).

## Testing without AWS

```bash
terraform init && terraform test
```

The tests use a fake AWS provider, so they need no credentials and create
nothing.
