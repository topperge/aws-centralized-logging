# Centralized Logging on AWS – Terraform

Terraform configuration for the Centralized Logging on AWS primary account. It replaces the
former AWS CDK app (`source/resources`), which synthesized the `CL-PrimaryStack` CloudFormation
template and its nested demo stack.

## Usage

```bash
# from the repository root: build the transformer Lambda package
npm ci && npm run build

cd terraform
cp terraform.tfvars.example terraform.tfvars   # edit values
terraform init
terraform apply
```

Then, in each spoke account/region, subscribe log groups to the destination using the
`destination_subscription_command` output.

### Inputs

| Variable | Default | Former CFN parameter | Description |
|---|---|---|---|
| `admin_email` | (required) | `AdminEmail` | Cognito admin user and alarm notification email |
| `spoke_accounts` | (required) | `SpokeAccounts` | Account IDs allowed to subscribe to the destinations |
| `spoke_regions` | `["All"]` | `SpokeRegions` | Regions to create CloudWatch Logs destinations in |
| `domain_name` | `centralizedlogging` | `DomainName` | Domain name |
| `cluster_size` | `Small` | `ClusterSize` | `Small` (4×r5.large), `Medium` (6×r5.2xlarge), `Large` (6×r5.4xlarge) data nodes, plus 3 c5.large masters |
| `deploy_demo` | `false` | `DemoTemplate` | Deploy sample log sources (`modules/demo`) |
| `deploy_jumpbox` | `false` | `JumpboxDeploy` | Deploy a Windows jumpbox in the domain VPC |
| `jumpbox_key` | `""` | `JumpboxKey` | EC2 key pair for the jumpbox |
| `region` | provider default | – | Primary region |
| `name_prefix` | `CL` | – | Prefix for named resources (`CL-Firehose`, `CL-Destination-<uuid>`, ...) |
| `engine_version` | `Elasticsearch_7.10` | – | Domain engine version |
| `ebs_volume_size` | `10` | – | EBS GiB per data node (the CDK default) |
| `create_es_service_linked_role` | `true` | – | Set `false` if `es.amazonaws.com`'s service-linked role already exists |
| `cognito_advanced_security_mode` | `ENFORCED` | – | `ENFORCED`/`AUDIT` use the Cognito PLUS tier, `OFF` uses ESSENTIALS |
| `transformer_zip_path` | `../source/services/transformer/dist/transformer/cl-transformer.zip` | – | Transformer Lambda package |
| `lambda_runtime` | `nodejs22.x` | – | Transformer runtime |
| `send_anonymized_metrics` | `true` | `CLMap.Metric.SendAnonymizedMetric` | Send anonymized usage metrics |

### Outputs

`destination_subscription_command`, `destination_arns`, `unique_id`, `admin_email`, `domain_name`,
`kibana_url`, `cluster_size`, `demo_deployment`, `demo_url`, `jumpbox_public_ip`.

## Mapping from the CloudFormation/CDK version

| CloudFormation/CDK | Terraform |
|---|---|
| `Custom::CreateUUID` (helper Lambda) | `random_uuid.solution` |
| `Custom::CreateESServiceRole` (helper Lambda) | `aws_iam_service_linked_role.es` |
| `Custom::CWDestination` (helper Lambda, one destination per spoke region) | `aws_cloudwatch_log_destination.spoke` / `aws_cloudwatch_log_destination_policy.spoke`, using the AWS provider v6 per-resource `region` argument |
| `Custom::LaunchData` (helper Lambda) | Removed – no launch metric is sent; the transformer still sends usage metrics when enabled |
| `AWS::Elasticsearch::Domain` | `aws_opensearch_domain.es` with `engine_version = "Elasticsearch_7.10"` |
| Nested `CL-DemoStack` (condition `demoDeploymentCheck`) | `module.demo` (`count` on `deploy_demo`) |
| Demo web server `AWS::CloudFormation::Init` | cloud-init user data (`modules/demo/templates/webserver-user-data.sh.tftpl`) |
| Jumpbox condition `JumpboxDeploymentCheck` | `count` on `deploy_jumpbox` |

### Behavioral differences

- **No in-place migration.** Terraform creates new resources; it does not adopt an existing
  CloudFormation stack. Deploy alongside (using a different `domain_name` and `name_prefix`) and move
  spokes over, or delete the old stack first. The Firehose name `CL-Firehose` and the CloudWatch Logs
  destination names collide with an existing stack unless `name_prefix` is changed.
- **Deletion/retention.** The CDK stack *retained* the domain VPC, security group, Firehose backup
  bucket, Cognito user pool and some log groups on stack deletion. Terraform has no retain policy:
  `terraform destroy` deletes them, except that non-empty S3 buckets fail to delete (no `force_destroy`).
- **Firehose log group.** The CDK version created its Firehose log group with a generated name while
  Firehose was configured to log to `/aws/kinesisfirehose/CL-Firehose`; Terraform creates the log
  group under the name Firehose actually uses.
- **Region validation** happens at plan time (precondition) instead of inside the helper Lambda, and
  `deploy_demo` checks at plan time that the primary account/region are listed as spokes.
- **Lambda runtime** defaults to `nodejs22.x`; `nodejs18.x` is deprecated and can no longer be used
  to create functions.
- **Cognito.** `ENFORCED` advanced security requires the Cognito PLUS feature tier (billed per MAU),
  which did not exist when the CDK version was written.

## Tests

```bash
terraform init -backend=false
terraform test
```

`tests/main.tftest.hcl` runs plan-only tests against mocked providers, so no AWS credentials are
needed. They cover cluster sizing, `"All"` region expansion, optional jumpbox/demo resources and the
input validations/preconditions.
