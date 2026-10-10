# Terraform State Ownership

This document defines who owns each part of the AWS Cloud Security project:
which Terraform state manages which AWS resources, who may change them, and
how they are deployed and removed. It describes the code in this repository.
`scripts/validate-ownership.py` checks the parts of it that can be checked
mechanically.

The core rule: **every AWS resource has exactly one owning state.** Other
root modules may *look a resource up*, but they never declare it.

---

## 1. Root modules and their states

| | `bootstrap` | `account-baseline` | `dev` | `staging` | `prod` |
|---|---|---|---|---|---|
| **Directory** | `bootstrap/` | `account-baseline/` | `environments/dev/` | `environments/staging/` | `environments/prod/` |
| **AWS account and Region scope** | One per account. Region of the state bucket (`aws_region`, default `us-east-1`). | One per account. Home Region (`aws_region`), plus optional `secondary_region` through the `aws.secondary` provider alias. CloudTrail is multi-Region. | The account in `TF_VAR_account_id`, Region `aws_region` | Same as dev | Same as dev |
| **State backend location** | **Local file** `bootstrap/terraform.tfstate` (`backend "local"`), backed up out of band (§6) | S3 bucket `acs-tfstate-<account_id>-<region>`, SSE-KMS with `alias/acs-tfstate`, versioned, `use_lockfile = true` | Same bucket | Same bucket | Same bucket |
| **State key** | n/a (local) | `aws-cloud-security/account-baseline/terraform.tfstate` | `aws-cloud-security/dev/terraform.tfstate` | `aws-cloud-security/staging/terraform.tfstate` | `aws-cloud-security/prod/terraform.tfstate` |
| **Resources managed** | State bucket `acs-tfstate-<acct>-<region>` with versioning, SSE-KMS, public access block, ownership controls, lifecycle, and isolation policy. State KMS key `alias/acs-tfstate`. Deployer roles `acs-tf-account-baseline`, `acs-tf-dev`, `acs-tf-staging`, `acs-tf-prod` (path `/acs/terraform/`) with their policies. Workload permission boundaries `acs-<env>-workload-boundary`. Generated `backend-config/<acct>-<region>.s3.tfbackend`. | GuardDuty detector and protection plans. Security Hub CSPM account, FSBP and CIS 3.0.0 standards, and the finding aggregator (when a second Region is set). AWS Config recorder, delivery channel, status, and `acs-baseline-*` managed rules. Multi-Region trail `acs-baseline-trail`, including S3 data events on the state bucket. KMS `alias/acs-baseline-security-logs`. Buckets `acs-baseline-cloudtrail-*` and `acs-baseline-config-*`. Log group `/acs/baseline/cloudtrail`. Roles `acs-baseline-cloudtrail-to-cwl` and `acs-baseline-config`. SNS topic `acs-baseline-security-alerts` and its three EventBridge rules. S3 account public access block. EBS encryption by default. IAM Access Analyzer `acs-baseline-account-analyzer`. | VPC `acs-dev` with subnets, IGW, route tables, and the default SG stripped. VPC Flow Logs. SGs `acs-dev-alb`, `-app`, `-db`. KMS `alias/acs-dev-workloads`. Log groups `/acs/dev/vpc-flow-logs` and `/acs/dev/application`. Roles `acs-dev-vpc-flow-logs` and `acs-dev-app` (with instance profile). Bucket `acs-dev-data-<acct>-<region>`. Rejected-flows metric filter and alarm. `environment_guard`. | Same set, named `acs-staging-*`, plus a NAT gateway | Same set, named `acs-prod-*`, across 3 AZs with a NAT gateway; KMS key, bucket and log groups protected from destroy |
| **Resources explicitly not managed** | Anything that uses the backend. Any security service. Any workload. | Terraform state infrastructure and deployer roles (bootstrap). VPCs, workload keys, buckets and roles (environments). | GuardDuty, Security Hub CSPM, Config, CloudTrail, the alerts topic and rules, the account public access block, EBS default encryption, Access Analyzer, the state bucket, deployer roles and boundaries. The GuardDuty detector, alerts topic and boundary are **read** through data sources only. | Same as dev | Same as dev |
| **Deployment dependencies** | AWS credentials for the target account that can create S3, KMS and IAM resources | bootstrap applied (bucket, key, `acs-tf-account-baseline` role, `.tfbackend` file) | bootstrap (bucket, `acs-tf-dev` role, `acs-dev-workload-boundary`) **and** account-baseline (GuardDuty detector, `acs-baseline-security-alerts` topic) | bootstrap and account-baseline | bootstrap and account-baseline |
| **Authorized deployment role** | Account administrator or break-glass identity, with MFA. It creates the roles below. | `arn:aws:iam::<acct>:role/acs/terraform/acs-tf-account-baseline` | `…:role/acs/terraform/acs-tf-dev` | `…:role/acs/terraform/acs-tf-staging` | `…:role/acs/terraform/acs-tf-prod` |
| **Cleanup considerations** | Destroy **last**, after every remote root has been destroyed or migrated. Bucket and key have `prevent_destroy`. Every state version must be removed first (§9.4). | Should outlive every environment (§8). Has `prevent_destroy` on the detector, hub, recorder, trail, topic, key, buckets, account public access block and EBS default. Decommission only with the reviewed procedure in §9.3. Log archives are usually *retained*, not deleted. | `terraform destroy` removes everything it owns (`protect_from_destroy = false`, `force_destroy_buckets = true`). The KMS key enters a 7-day deletion window. | `protect_from_destroy = false` but the bucket is not force-destroyed: empty it or apply `-var force_destroy_buckets=true` before destroying (§9.1). | KMS key and data bucket use `prevent_destroy`; log groups use `skip_destroy`. Destroy requires the explicit procedure in §9.2. |

`<acct>` and `<region>` stand for the 12-digit account ID and Region you
bootstrapped (`TF_VAR_account_id`, `aws_region`).

### How each guarantee is implemented

| Guarantee | Where it is enforced |
|---|---|
| Separate state per root | A different `key` in each `*/backend.tf`; bootstrap uses `backend "local"` |
| Only one root may write a key | State bucket policy statement `IsolateStateScope<Scope>` denies `Get/Put/DeleteObject` under `aws-cloud-security/<scope>/` to every principal except `acs-tf-<scope>` (and `break_glass_principal_arns`) — `bootstrap/main.tf` |
| Deployer roles touch only their own state | Inline policy `terraform-state-<scope>` grants only `<key>` and `<key>.tflock` — `bootstrap/iam.tf` |
| Environments cannot change the baseline | Explicit `Deny` statements (`protect_account_baseline`) on the environment deployer roles **and** on every workload role through the permissions boundary — `bootstrap/iam.tf` |
| Environments cannot mint privileged roles | `iam:CreateRole` allowed only with `iam:PermissionsBoundary = acs-<env>-workload-boundary`; boundary removal denied |
| Wrong-account protection | `allowed_account_ids` in every provider **and** in the generated `.tfbackend` (the S3 backend checks it too) |
| Wrong-environment protection | `terraform_data.environment_guard` fails the plan if `environment` ≠ directory name |
| Baseline must exist first | Environments read `data.aws_guardduty_detector` and `data.aws_sns_topic`; the plan fails if they are missing |

---

## 2. Sharing module source code is not sharing state

The `modules/` directory holds **source code**. A module call such as

```hcl
module "kms" {
  source = "../../modules/kms-key"
  ...
}
```

copies that code into the calling root. Every root that calls a module gets
**its own instances** of the module's resources, recorded in **its own**
state file. `dev`, `staging` and `prod` share byte-identical `main.tf`,
`variables.tf`, `outputs.tf`, `providers.tf` and `versions.tf` (the validator
checks this). They still produce three separate VPCs, keys and buckets,
tracked in three separate state files:

```
module.kms.aws_kms_key.unprotected[0]   in aws-cloud-security/dev/terraform.tfstate     -> alias/acs-dev-workloads
module.kms.aws_kms_key.unprotected[0]   in aws-cloud-security/staging/terraform.tfstate -> alias/acs-staging-workloads
module.kms.aws_kms_key.protected[0]     in aws-cloud-security/prod/terraform.tfstate    -> alias/acs-prod-workloads
```

`modules/kms-key`, `modules/secure-s3-bucket`, `modules/cloudwatch-log-group`
and `modules/iam-role` are used by bootstrap, the baseline and all three
environments. That is **code reuse**: the same hardening rules in five
places, with five independent owners.

**Sharing state** would mean two roots reading or writing the *same* state
file, or declaring the *same* physical resource. This project never does
either:

* No root uses `terraform_remote_state`. Environments find baseline
  resources with ordinary data sources (`aws_guardduty_detector`,
  `aws_sns_topic`, `aws_iam_policy`). Their deployer roles therefore never
  need read access to the baseline's state, which may contain sensitive
  attributes.
* Account-level modules (`guardduty`, `securityhub`, `aws-config`,
  `cloudtrail`, `security-alerting`) are called **only** by
  `account-baseline`.

A shared-module change does reach every root, but only when each root is
re-planned and applied by its own deployer. Review it as a change to every
caller; CODEOWNERS routes `modules/` to both platform and security
engineering.

---

## 3. Why a resource must never be managed by two states

Terraform assumes that whatever is in its state is **exclusively** its own.
When two independent states declare the same physical resource:

1. **Some resources are account singletons and cannot be duplicated.** AWS
   allows one GuardDuty detector, one Security Hub CSPM subscription, and one
   Config recorder and delivery channel per account per Region. If `dev` and
   `prod` both declared `aws_guardduty_detector`, the second apply would fail.
   Or worse, someone would `terraform import` the existing detector into the
   second state "to make it work". Now two states own one detector.
2. **Destroy in one state deletes the other's resource.** `terraform
   destroy` in `dev` would delete the shared detector, disable Security
   Hub, or stop the Config recorder. Production would silently lose threat
   detection, and the `prod` state would still say everything is fine until
   its next refresh.
3. **Configuration flip-flops.** Each state pushes its own arguments. If
   `staging` sets GuardDuty findings to `SIX_HOURS` and the baseline sets
   `FIFTEEN_MINUTES`, every apply in one state reverts the other.
   Change history becomes meaningless.
4. **Locking does not protect you.** `use_lockfile` locks **one state
   key**. Two states have two lock files, so two concurrent applies against
   the same resource proceed in parallel and race.
5. **Ownership and blast radius become unclear.** Reviewers can no longer
   answer "what does this apply affect?" by reading one root module, and IAM
   cannot express "dev may not touch the account baseline".

So every account-level resource lives in `account-baseline`, and
environments only reference it. The validator fails if any account-level
resource type is reachable from another root, or if a singleton type is
declared by more than one root.

---

## 4. Backend configuration

Each remote-state root has a `backend.tf` with **only** the values specific
to that root:

```hcl
# environments/dev/backend.tf
terraform {
  backend "s3" {
    key          = "aws-cloud-security/dev/terraform.tfstate"
    encrypt      = true
    use_lockfile = true
  }
}
```

The account-specific values are supplied at init from the file bootstrap
generates, `backend-config/<account_id>-<region>.s3.tfbackend`:

```hcl
bucket              = "acs-tfstate-<account_id>-<region>"
region              = "<region>"
kms_key_id          = "arn:aws:kms:<region>:<account_id>:key/<key-id>"
allowed_account_ids = ["<account_id>"]
```

| Setting | Purpose |
|---|---|
| `key` | Unique per root (§1). Never reused. |
| `use_lockfile = true` | Native S3 locking: Terraform writes `<key>.tflock` with a conditional put. No DynamoDB table needed. Each deployer role may write and delete only its own lock file. |
| `encrypt = true` + `kms_key_id` | State is encrypted with the customer managed key `alias/acs-tfstate`. The bucket policy rejects any non-KMS encryption header. |
| `allowed_account_ids` | The backend refuses to run if the caller's credentials belong to another account. |
| Credentials | **Never** in `backend.tf` or `.tfbackend`. They come from `AWS_PROFILE`, SSO or CI OIDC. The validator rejects `access_key`, `secret_key`, `token`, `profile` and shared-credentials settings. |

### Multi-account deployments

When `dev`, `staging` and `prod` live in separate AWS accounts, **each account
is bootstrapped separately** and gets:

* its **own state bucket**, `acs-tfstate-<that_account_id>-<region>`. The
  account ID in the name makes it impossible for two accounts to resolve to
  the same state location;
* its **own** `backend-config/<that_account_id>-<region>.s3.tfbackend` with
  `allowed_account_ids = ["<that_account_id>"]`;
* its **own** `account-baseline` state at
  `aws-cloud-security/account-baseline/terraform.tfstate`, inside that
  account's bucket;
* only the scopes it hosts, e.g. `state_scopes = ["account-baseline", "prod"]`.

```bash
# Production account
export TF_VAR_account_id=<prod_account_id>
terraform -chdir=bootstrap apply -var 'state_scopes=["account-baseline","prod"]'
```

Then initialise `account-baseline` and `environments/prod` against
`backend-config/<prod_account_id>-us-east-1.s3.tfbackend`. Repeat for the dev
and staging accounts. The root module code is unchanged; only the backend
file and `TF_VAR_account_id` differ. Switching an already initialised
`account-baseline/` directory to another account requires
`terraform init -reconfigure -backend-config=<other file>`. Use a separate
checkout or CI job per account to avoid mixing them up.

If you prefer one central state bucket in a dedicated account, keep the
per-account isolation by giving each account its own key prefix, for example
`key = "aws-cloud-security/<account_id>/dev/terraform.tfstate"` passed as an
additional `-backend-config=key=...` argument. Also extend the bucket policy's
`IsolateStateScope*` statements to those prefixes. That is not the default
layout of this repository.

---

## 5. Deployment order

```
1. bootstrap ──► 2. account-baseline ──► 3. dev
                                     ├─► 4. staging
                                     └─► 5. prod
                                          ──► 6. validate
```

### Prerequisites

* Terraform ≥ 1.11 (`use_lockfile`). Tested with 1.16.
* AWS CLI v2.
* For bootstrap: credentials for an administrator in the target account.
* `export TF_VAR_account_id=<12-digit account id>`. Type it deliberately; do
  not derive it from whatever credentials happen to be active.

### Step 1: Bootstrap the backend

```bash
cd bootstrap
terraform init
terraform plan -out=tfplan
terraform apply tfplan
terraform output            # bucket, key ARN, deployer roles, backend config path
cd ..
```

Then protect the local state (§6) **before** continuing.

Configure one AWS CLI profile per deployer role, for example in
`~/.aws/config`:

```ini
[profile acs-baseline]
role_arn       = arn:aws:iam::<acct>:role/acs/terraform/acs-tf-account-baseline
source_profile = <your-admin-or-sso-profile>
mfa_serial     = arn:aws:iam::<acct>:mfa/<your-mfa-device>

[profile acs-dev]
role_arn       = arn:aws:iam::<acct>:role/acs/terraform/acs-tf-dev
source_profile = <your-admin-or-sso-profile>
mfa_serial     = arn:aws:iam::<acct>:mfa/<your-mfa-device>
# ...same for acs-staging and acs-prod
```

When the trusted principals are IAM Identity Center permission-set roles or
CI OIDC roles, list them in `deployer_trusted_principal_arns` and set
`require_mfa = false`. In that setup MFA is enforced by the identity provider,
and AWS does not set `aws:MultiFactorAuthPresent` on those sessions.

### Step 2: Account-security baseline

```bash
cd account-baseline
AWS_PROFILE=acs-baseline terraform init -backend-config=../backend-config/${TF_VAR_account_id}-us-east-1.s3.tfbackend
AWS_PROFILE=acs-baseline terraform plan -out=tfplan
AWS_PROFILE=acs-baseline terraform apply tfplan
cd ..
```

Account-wide dependencies that must exist before step 3:

* GuardDuty detector enabled in the environment Region. Environments fail
  at plan time without it.
* SNS topic `acs-baseline-security-alerts`. Environment alarms publish to it.
  Confirm the email subscriptions.
* AWS Config recording. The `acs-baseline-vpc-flow-logs-enabled` and related
  rules evaluate the environments as they are created.
* CloudTrail logging. Records every environment deployment.

If GuardDuty, Security Hub CSPM or a Config recorder **already exists** in the
account (enabled by hand or by another tool), import it into
`account-baseline` instead of creating a second owner:

```bash
AWS_PROFILE=acs-baseline terraform import 'module.guardduty_home.aws_guardduty_detector.this' <detector-id>
AWS_PROFILE=acs-baseline terraform import 'module.securityhub_home.aws_securityhub_account.this' <account_id>
AWS_PROFILE=acs-baseline terraform import 'module.config_home.aws_config_configuration_recorder.this' <recorder-name>
AWS_PROFILE=acs-baseline terraform import 'module.config_home.aws_config_delivery_channel.this' <channel-name>
```

Then remove the resources from whatever previously managed them.

### Steps 3–5: Environments

```bash
for env in dev staging prod; do
  (cd environments/$env &&
   AWS_PROFILE=acs-$env terraform init -backend-config=../../backend-config/${TF_VAR_account_id}-us-east-1.s3.tfbackend &&
   AWS_PROFILE=acs-$env terraform plan -out=tfplan &&
   AWS_PROFILE=acs-$env terraform apply tfplan)
done
```

Once steps 1 and 2 are done, **each environment is independent**. They can
be deployed in any order, in parallel, by different teams, and re-applied or
destroyed without affecting each other or the baseline. The order
dev → staging → prod is a promotion convention, not a technical dependency.

### Step 6: Validate integrations and ownership

```bash
# Static ownership rules (no AWS access)
python3 scripts/validate-ownership.py

# Mocked plans/applies of every root (no AWS access)
for r in bootstrap account-baseline environments/dev environments/staging environments/prod; do
  (cd $r && terraform init -backend=false -input=false >/dev/null && terraform test)
done

# Live integrations
aws guardduty list-detectors
aws securityhub get-enabled-standards --query 'StandardsSubscriptions[].StandardsArn'
aws configservice describe-configuration-recorder-status
aws cloudtrail get-trail-status --name acs-baseline-trail --query IsLogging
aws configservice get-compliance-details-by-config-rule --config-rule-name acs-baseline-vpc-flow-logs-enabled
aws ec2 describe-flow-logs --filter Name=tag:TerraformRoot,Values=dev,staging,prod

# Every resource carries its owner
aws resourcegroupstaggingapi get-resources --tag-filters Key=TerraformRoot,Values=account-baseline --query 'ResourceTagMappingList[].ResourceARN'
aws resourcegroupstaggingapi get-resources --tag-filters Key=TerraformRoot,Values=dev --query 'ResourceTagMappingList[].ResourceARN'

# Each key exists once, with its own lock lifecycle and version history
aws s3api list-objects-v2 --bucket acs-tfstate-${TF_VAR_account_id}-us-east-1 --prefix aws-cloud-security/ --query 'Contents[].Key'
```

The `TerraformRoot` tag comes from each root's provider `default_tags`, and
`StateKey`/`StateLocation` records where that root's state lives. A resource
tagged with one root but listed in another's `terraform state list` signals a
double-ownership bug.

---

## 6. Protecting the bootstrap state

`bootstrap/terraform.tfstate` is the only local state file. It is small, but
it maps the state bucket, the state KMS key and every deployer role to real
AWS objects. Losing it makes bootstrap changes painful; leaking it reveals
the account's state architecture.

1. **Never commit it.** `.gitignore` excludes `*.tfstate*`.
2. **Encrypt a copy immediately after every bootstrap apply**, and keep it
   where the account's break-glass material lives (a password manager vault
   or an offline encrypted volume):
   ```bash
   age -r <security-team-recipient> -o bootstrap-$(date +%F).tfstate.age bootstrap/terraform.tfstate
   ```
3. **Restrict the working copy:** `chmod 600 bootstrap/terraform.tfstate` on a
   trusted, full-disk-encrypted workstation. Delete it from laptops that do
   not need it.
4. **Re-run rarely.** Bootstrap changes only when roles, scopes or the bucket
   policy change. Every such change goes through security-engineering review
   (CODEOWNERS).
5. **It can be rebuilt.** Every bootstrap resource has a deterministic name.
   If the file is lost, recreate it with `terraform import` (state bucket
   `acs-tfstate-<acct>-<region>`, alias `alias/acs-tfstate`, roles
   `acs-tf-*`, policies `acs-<env>-workload-boundary`) and confirm that
   `terraform plan` shows no changes.
6. **Optional migration.** After the bucket exists, you may move bootstrap's
   state into it. Add a `backend "s3"` block with
   `key = "aws-cloud-security/bootstrap/terraform.tfstate"`, add `bootstrap`
   to the bucket-policy isolation, and run `terraform init -migrate-state`.
   The trade-off: if the bucket or key is ever misconfigured, the tool that
   repairs it cannot read its own state. This project keeps bootstrap local
   by default.

---

## 7. Safeguards for shared security resources

| Safeguard | Implementation |
|---|---|
| Terraform lifecycle protection | `prevent_destroy = true` on the GuardDuty detector, Security Hub CSPM account, Config recorder, CloudTrail trail and alerts topic (hard-coded in their modules; only the baseline calls them). Also on the S3 account public access block and EBS default encryption in `account-baseline/main.tf`, and on the state and baseline KMS keys and buckets (`prevent_destroy = true` module input). `skip_destroy` on `/acs/baseline/cloudtrail`. |
| Restricted IAM | One deployer role per root. Environment roles carry explicit `Deny` on every GuardDuty, Security Hub, Config, CloudTrail and Access Analyzer mutation. They are also denied the account public access block, EBS default encryption, `acs-baseline-*` topics, rules, buckets, log groups and roles, `acs-tfstate`/`acs-baseline-*` KMS keys and aliases, and the deployer roles and boundaries. Workload roles inherit the same denies through `acs-<env>-workload-boundary`. |
| Review and approval | `.github/CODEOWNERS` requires security engineering for `bootstrap/`, `account-baseline/`, `backend-config/`, `modules/` and `environments/prod/`. Apply only from a reviewed `plan -out` file. Baseline decommissioning additionally requires the change in §9.3. |
| S3 versioning | Every bucket the modules create is versioned. State versions are kept for 365 days (`state_noncurrent_version_retention_days`). `s3:DeleteObjectVersion` on the state bucket is denied to everyone except `break_glass_principal_arns`. |
| Secure state access | SSE-KMS with a dedicated key. TLS ≥ 1.2 enforced. Public access blocked. Per-scope bucket-policy isolation. CloudTrail S3 data events record every state read and write. `allowed_account_ids` set in the backend and provider. |
| Tamper detection | EventBridge rule `acs-baseline-security-alerts-security-tampering` alerts on `StopLogging`, `DeleteTrail`, `DeleteDetector`, `DisableSecurityHub`, `StopConfigurationRecorder` and similar calls, including calls made outside Terraform. |
| Explicit cleanup | §9: environment destroy never targets baseline resources; baseline and bootstrap decommissioning are separate, deliberate procedures. |

**Environment destruction cannot reach account-level resources.** Three
independent controls guarantee this:

1. **State scope.** `terraform destroy` in `environments/dev` only acts on
   resources recorded in `aws-cloud-security/dev/terraform.tfstate`. Baseline
   resources are referenced as `data` sources, and Terraform never destroys
   data sources.
2. **Code.** The validator fails if any account-level resource type is
   reachable from an environment root.
3. **IAM.** Even if (1) and (2) were bypassed, `acs-tf-dev` is explicitly
   denied every action needed to delete or disable baseline resources.

---

## 8. Why the baseline outlives environments

* **It protects the account, not an application.** GuardDuty, Security Hub
  CSPM, Config and CloudTrail must already be running when an environment is
  created, so that its creation is recorded and evaluated. They must also
  keep running while it is destroyed, so that the teardown is recorded and
  evaluated too.
* **Evidence must survive the thing it describes.** CloudTrail logs, Config
  history and findings about a deleted environment are exactly what an
  incident review or audit asks for.
* **It is shared.** In a single-account layout, three environments depend
  on one detector, one hub, one recorder and one alerts topic. Removing it
  for one environment removes it for all.
* **Gaps are expensive.** Re-enabling GuardDuty resets its learned baseline.
  A stopped trail is a hole in the audit record that cannot be filled
  afterwards.
* **Different change cadence.** Environments are created and destroyed
  routinely. The baseline changes rarely and under stricter review.

---

## 9. Cleanup procedures

### 9.1 dev and staging

```bash
cd environments/dev
AWS_PROFILE=acs-dev terraform plan -destroy -out=destroy.tfplan
# Review: every address must be module.vpc/*, module.kms/*, module.data_bucket/*,
# module.*_log_group/*, module.*_role/*, module.security_groups/*,
# aws_cloudwatch_*.rejected_flows or terraform_data.environment_guard.
AWS_PROFILE=acs-dev terraform apply destroy.tfplan
```

For **staging**, `force_destroy_buckets = false` keeps versioned data unless
you explicitly allow its removal:

```bash
cd environments/staging
AWS_PROFILE=acs-staging terraform apply   -var force_destroy_buckets=true
AWS_PROFILE=acs-staging terraform destroy -var force_destroy_buckets=true
```

The environment's KMS key enters its deletion window (7 days in dev, 30 in
staging and prod). The account baseline, the state bucket and the other
environments are untouched. The environment's state object stays in the
bucket, empty, with its version history. You may delete the current
version; old versions expire under the lifecycle rule.

### 9.2 prod (protected resources)

In prod, `terraform destroy` fails by design on `module.kms` and
`module.data_bucket`. Removing them is a deliberate, reviewed sequence:

1. Approve the decommission in change management. Export or snapshot any
   data that must be retained.
2. Move the protected instances to their unprotected twins. These are state
   moves only; nothing in AWS changes:
   ```bash
   cd environments/prod
   AWS_PROFILE=acs-prod terraform state mv 'module.kms.aws_kms_key.protected[0]'          'module.kms.aws_kms_key.unprotected[0]'
   AWS_PROFILE=acs-prod terraform state mv 'module.data_bucket.aws_s3_bucket.protected[0]' 'module.data_bucket.aws_s3_bucket.unprotected[0]'
   ```
3. In a reviewed change, set `protect_from_destroy = false` (and, if the
   data may be deleted, `force_destroy_buckets = true`) in
   `environments/prod/terraform.tfvars`.
4. `terraform plan` must show **no replacements**, only in-place updates
   such as `skip_destroy` on the log groups. Apply it.
5. `terraform plan -destroy -out=destroy.tfplan`, review, then apply.

To keep the logs, the data bucket or the key in AWS while removing them from
Terraform, use a `removed` block with `lifecycle { destroy = false }` for
those addresses instead of step 3.

### 9.3 account-baseline (decommissioning an account)

The baseline is decommissioned only when the account itself is retired, or
when its security services move to organization-level delegated
administration. Never as part of removing an environment.

1. Destroy or migrate **every** environment in the account first (§9.1–9.2).
   `aws resourcegroupstaggingapi get-resources --tag-filters Key=TerraformRoot,Values=dev,staging,prod`
   must return nothing.
2. Obtain security-engineering approval. Disabling GuardDuty, Security Hub
   CSPM, Config or CloudTrail triggers the tampering alert, so announce the
   window.
3. Decide what is **retained**. CloudTrail and Config archives usually have
   a legal retention period. For `module.cloudtrail_bucket`,
   `module.config_bucket`, `module.security_logs_kms` and
   `module.cloudtrail_log_group`, replace each module block with
   `removed { from = module.<name>  lifecycle { destroy = false } }` so they
   leave state without being deleted.
4. In a dedicated reviewed change, remove `prevent_destroy` from
   `modules/guardduty`, `modules/securityhub`, `modules/aws-config`,
   `modules/cloudtrail`, `modules/security-alerting` and the guardrail
   resources in `account-baseline/main.tf`. Do the same for any key or
   bucket not being retained, using the `state mv` technique from §9.2.
5. `AWS_PROFILE=acs-baseline terraform plan -destroy -out=destroy.tfplan`,
   review every address, then apply.

### 9.4 bootstrap (last)

Only after every remote-state root in the account has been destroyed or
migrated elsewhere:

1. Confirm that `aws s3api list-objects-v2 --bucket acs-tfstate-<acct>-<region>`
   lists no state you still need.
2. A break-glass principal deletes every object version (the bucket policy
   denies `s3:DeleteObjectVersion` to everyone else).
3. Use the `state mv` technique from §9.2 for `module.state_kms` and
   `module.state_bucket`, set `prevent_destroy = false` on both module calls,
   and apply.
4. `terraform destroy`. Then delete the generated
   `backend-config/<acct>-<region>.s3.tfbackend` and the encrypted bootstrap
   state backups.

---

## 10. Inspecting state

```bash
# bootstrap (local)
terraform -chdir=bootstrap state list
terraform -chdir=bootstrap output deployer_role_arns

# account-baseline
cd account-baseline
AWS_PROFILE=acs-baseline terraform state list
AWS_PROFILE=acs-baseline terraform state show 'module.guardduty_home.aws_guardduty_detector.this'
cd ..

# environments
cd environments/prod
AWS_PROFILE=acs-prod terraform state list
AWS_PROFILE=acs-prod terraform state list | grep -E 'guardduty|securityhub|config_|cloudtrail' \
  || echo "OK: no account-level resources in prod state"
cd ../..

# Raw state objects and their history
aws s3api list-object-versions --bucket acs-tfstate-${TF_VAR_account_id}-us-east-1 \
  --prefix aws-cloud-security/prod/terraform.tfstate --query 'Versions[].[VersionId,LastModified]'
```

Data sources (`data.aws_guardduty_detector.baseline[0]`,
`data.aws_sns_topic.security_alerts[0]`, `data.aws_iam_policy.workload_boundary`)
appear in an environment's `state list`. They are read-only snapshots, not
managed resources.
