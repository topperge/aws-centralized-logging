# Centralized Logging on AWS Solution
**Centralized Logging on AWS has been superseded by the Centralized Logging with OpenSearch [Centralized Logging with OpenSearch](https://aws.amazon.com/solutions/implementations/centralized-logging-with-opensearch/) solution. All existing deployments will continue to work but the solution will no longer be supported and maintained.**

## Table of content

- [Solution Overview](#solution-overview)
- [Architecture](#architecture)
- [Installation](#installing-pre-packaged-solution-template)
- [Customization](#customization)
  - [Setup](#setup)
  - [Changes](#changes)
  - [Unit Test](#unit-test)
  - [Build](#build)
  - [Deploy](#deploy)
- [Sample Scenario](#sample-scenario)
- [File Structure](#file-structure)
- [License](#license)

## Solution Overview

Centralized Logging on AWS is a reference implementation that provides a foundation for logging to a centralized account. Customers can leverage the solution to index CloudTrail Logs, CW Logs, VPC Flow Logs on an Amazon OpenSearch Service domain. The logs can then be searched on different fields.

This solution gives you a turnkey environment to begin logging and analyzing your AWS environment and applications. Additionally, if you are looking to

- collect logs from multiple AWS accounts and organizations
- collect logs from multiple regions
- a single pane view for log analysis and visualization

then you can get all this with a single `terraform apply`.

This solution uses Amazon OpenSearch Service (successor to Amazon Elasticsearch Service) and Kibana, an analytics and visualization platform that is integrated with Amazon OpenSearch Service, that results in a unified view of all the log events.

## Architecture

The Centralized Logging on AWS solution contains the following components: **log ingestion**, **log indexing**, and **visualization**. You must deploy the Terraform configuration in the AWS account where you intend to store your log data.

<img src="./architecture.png" width="750" height="500">

## Customization

- Prerequisites: Node.js >= 18 | npm >= 8 | Terraform >= 1.5 (>= 1.7 to run `terraform test`)

### Setup

Clone the repository and run the following commands to install dependencies, format and lint as per the project standards

```
npm ci
npm run prettier-format
npm run lint
```

### Changes

The infrastructure is defined with Terraform in the [terraform](./terraform) directory. Opinionated defaults (cluster sizing, names, runtimes, ...) are exposed as input variables in [variables.tf](./terraform/variables.tf). You can also control sending solution usage metrics to aws-solutions with the `send_anonymized_metrics` variable.

### Unit Test

You can run unit tests (transformer build, `terraform validate` and the mocked `terraform test` suite) with the following command from the root of the project

```
 npm run test
```

### Build

You can build the transformer lambda package with the following command from the root of the project. Terraform deploys the resulting `source/services/transformer/dist/transformer/cl-transformer.zip`.

```
 npm run build
```

### Deploy

Deploys all the primary solution components needed for Centralized Logging on AWS. **Deploy in Primary Account**

```
npm run build
cd terraform
cp terraform.tfvars.example terraform.tfvars   # set admin_email, spoke_accounts, spoke_regions, ...
terraform init
terraform apply
```

See the [Terraform README](./terraform/README.md) for all inputs, outputs, and notes on migrating from the CloudFormation/CDK version.

## Sample Scenario (Enabling CloudWatch logging on Elasticsearch domain)

In this scenario let's say we want to enable CloudWatch logging for the ES domain. You would add `log_publishing_options` blocks to the `aws_opensearch_domain.es` resource in [opensearch.tf](./terraform/opensearch.tf), along with a CloudWatch Logs resource policy allowing `es.amazonaws.com` to write to the log group:

```
  log_publishing_options {
    log_type                 = "ES_APPLICATION_LOGS"
    cloudwatch_log_group_arn = aws_cloudwatch_log_group.es_application.arn
  }
```

## File structure

Centralized Logging on AWS solution consists of:

- Terraform configuration to provision the needed resources
- transformer to translate kinesis data stream records into Elasticsearch documents

<pre>
|-config_files                    [ config files for prettier, eslint etc. ]
|-architecture.png                [ solution architecture diagram ]
|-terraform/
  |-*.tf                          [ primary deployment: VPC, Cognito, domain, Kinesis, Firehose, destinations, jumpbox ]
  |-modules/demo/                 [ optional sample log sources: web server, VPC flow logs, CloudTrail ]
  |-tests/                        [ terraform test suite using mocked providers ]
  |-terraform.tfvars.example      [ example input values ]
|-source/
  |dashboard.ndjson               [ sample dashboard for demo ]
  |run-unit-test.sh               [ script to run unit tests ]
  |-services/
    |-@aws-solutions/utils/       [ library with generic utility functions for microservice ]
    |-transformer/                [ microservice to translate kinesis records into es documents ]
</pre>

## License

See license [here](./LICENSE.txt)


---

Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.

Licensed under the Apache License Version 2.0 (the "License"). You may not use this file except in compliance with the License. A copy of the License is located at

```
http://www.apache.org/licenses/LICENSE-2.0
```

or in the ["license"](./LICENSE.txt) file accompanying this file. This file is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, express or implied. See the License for the specific language governing permissions and limitations under the License.
