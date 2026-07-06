# Score Workload Module - AWS Lambda Deployment

Terraform module for deploying containerized Score workloads to AWS Lambda. This module handles Lambda function provisioning, IAM permissions, and container runtime configuration.

## Overview

This module encapsulates the deployment of a single containerized workload to AWS Lambda. It is designed to work within a Score and Humanitec Platform Orchestrator ecosystem where:

- **Score defines** the container image, command, environment variables, and required resources
- **This module provisions** the Lambda function and related AWS infrastructure
- **Other modules** provision additional resources (databases, storage, etc.) referenced by the container

The module focuses exclusively on the compute layer (`score-workload` resource type), while other resources (postgres, s3, etc.) are provisioned by dedicated modules.

## How It Works

### Flow: Score → Humanitec → Terraform

1. **Score File** defines a workload with:
   - Container image, command, and args
   - References to additional resources (e.g., `${resources.db.host}`)
   - Environment variables mapping

2. **Humanitec Platform Orchestrator** processes the Score file and:
   - Matches resource types to Resource Definitions
   - Invokes appropriate drivers/modules (this one for `score-workload`)
   - Passes container config and resource outputs to this module

3. **This Terraform Module** creates:
   - AWS Lambda function with container image
   - IAM execution role with CloudWatch Logs permissions
   - CloudWatch Log Group for function output
   - Environment variables injected from Score file

4. **Container Execution** receives:
   - Resolved resource outputs (e.g., `DB_HOST=postgres.example.com`)
   - Function context (memory, timeout, etc.)
   - CloudWatch integration for logging

## Answers to Implementation Questions

### 1. Which values/variables are passed from the score file into this module?

**From Score file:**
- Container image URI
- Container command and args
- Environment variable mappings: `${resources.resourceId.outputName}`
- Resource references that resolve to outputs from other modules

**From Humanitec Platform Orchestrator:**
- Resolved resource outputs (actual values replacing placeholders)
- Lambda configuration (memory, timeout)

**Example Score snippet:**
```yaml
containers:
  workload:
    image: my-registry/my-app:latest
    command: ["/app/bin/start"]
    args: ["--log-level=info"]
    variables:
      DB_HOST: ${resources.postgres.host}
      DB_PORT: ${resources.postgres.port}
      DB_USER: ${resources.postgres.user}
      CACHE_URL: ${resources.redis.url}

resources:
  postgres:
    type: postgres
  redis:
    type: redis
```

**Passed to this module as Terraform variables:**
- `container_image`: Image URI (string)
- `container_command`: Command array (list of strings)
- `container_args`: Args array (list of strings)
- `environment_variables`: Resolved environment variables (map of strings)

### 2. How is the container injected?

Containers are injected via **AWS Lambda container images**:

1. Container image must be pushed to ECR or other container registry
2. This module receives image URI as `container_image` input variable
3. Lambda function created with `image_uri` pointing to container
4. Container runtime configured with:
   - Entry point (command)
   - Arguments (args)
   - Environment variables (from Score resources + module inputs)

**Important**: The container must be compatible with Lambda's container execution model:
- Must listen on port 9000 for Lambda Runtime Interface Emulator (if using custom runtime)
- Or use AWS-provided base images supporting Lambda runtime interface
- Execution time limited by `timeout` (default 60s, max 900s)

### 3. What happens to additional resources required in the score file?

Additional resources (databases, storage, caches) are **provisioned by separate Terraform modules**, not this one:

1. **Score declares all resources:**
   ```yaml
   resources:
     postgres:
       type: postgres        # Provisioned by postgres module
     s3:
       type: s3              # Provisioned by s3 module
     redis:
       type: redis           # Provisioned by redis module
   ```

2. **Humanitec Platform Orchestrator resolves resource types** to Resource Definitions, each invoking appropriate drivers/modules

3. **Resource outputs become module outputs**, which are passed as environment variables to this module:
   ```hcl
   module "postgres" {
     source = "../postgres"
     # ...
   }

   module "redis" {
     source = "../redis"
     # ...
   }

   module "score_workload" {
     source = "./score-workload"
     environment_variables = {
       DB_HOST    = module.postgres.host
       DB_PORT    = module.postgres.port
       CACHE_URL  = module.redis.url
     }
   }
   ```

4. **This module does not manage** resource provisioning—only receives resolved outputs and makes them available to the container

### 4. How can you control the resource-type the score container gets deployed to?

**Resource type is NOT hardcoded to `score-workload`**—it's configurable via Humanitec Resource Definitions:

- **Built-in types** (e.g., `postgres`, `s3`) can be extended or overridden
- **Custom Resource Types** can map any Score `type` to any driver/module
- **This module** handles the `score-workload` resource type by convention

**To deploy to a different target** (e.g., ECS, Kubernetes):
1. Create a new Resource Definition pointing to a different driver
2. Register it with a different `type` name
3. Score would reference: `type: score-workload-ecs` or `type: score-workload-k8s`
4. Platform Orchestrator routes to appropriate module

**Reference docs:**
- [Custom Resource Types](https://developer.humanitec.com/platform-orchestrator/docs/platform-orchestrator/resources/custom-resource-types/)

## Module Variables

### Required Inputs

| Variable | Type | Description |
|----------|------|-------------|
| `container_image` | `string` | ECR or container registry URI for the workload image |
| `environment_variables` | `map(string)` | Environment variables passed to container (resource outputs + custom vars) |

### Optional Inputs

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `function_name` | `string` | `"score-workload"` | Lambda function name |
| `memory_size` | `number` | `256` | Lambda memory allocation (128-10240 MB) |
| `timeout` | `number` | `60` | Function timeout in seconds (1-900) |
| `ephemeral_storage_size` | `number` | `512` | Ephemeral storage in MB (512-10240) |
| `architectures` | `list(string)` | `["x86_64"]` | Lambda CPU architectures (`x86_64` or `arm64`) |
| `package_type` | `string` | `"Image"` | Lambda package type (`Zip` or `Image`). Always `Image` for this module |
| `log_retention_days` | `number` | `7` | CloudWatch Log Group retention (1-3653 days) |

### Environment Variables Example

```hcl
environment_variables = {
  DB_HOST       = "postgres.example.com"
  DB_PORT       = "5432"
  DB_USER       = "app_user"
  DB_PASSWORD   = "secret"
  CACHE_URL     = "redis://redis.example.com:6379"
  LOG_LEVEL     = "info"
  ENVIRONMENT   = "production"
}
```

## Module Outputs

| Output | Type | Description |
|--------|------|-------------|
| `function_arn` | `string` | Lambda function ARN |
| `function_name` | `string` | Lambda function name |
| `function_role_arn` | `string` | IAM execution role ARN |
| `log_group_name` | `string` | CloudWatch Log Group name |
| `log_group_arn` | `string` | CloudWatch Log Group ARN |

## Example Usage

### Basic Example

```hcl
module "score_workload" {
  source = "./modules/score-workload"

  function_name       = "my-api-workload"
  container_image     = "123456789.dkr.ecr.us-east-1.amazonaws.com/my-app:v1.0.0"
  memory_size         = 512
  timeout             = 120
  log_retention_days  = 14

  environment_variables = {
    ENVIRONMENT = "production"
    LOG_LEVEL   = "info"
  }
}
```

### Multi-Module Example (with resource modules)

```hcl
# Provision supporting resources
module "postgres" {
  source = "./modules/postgres"
  
  database_name = "my_app_db"
  engine        = "postgres"
  # ...
}

module "redis" {
  source = "./modules/redis"
  
  engine_version = "7.0"
  # ...
}

# Deploy workload with resource references
module "score_workload" {
  source = "./modules/score-workload"

  function_name   = "my-api"
  container_image = "123456789.dkr.ecr.us-east-1.amazonaws.com/api:latest"
  memory_size     = 512
  timeout         = 60

  environment_variables = {
    DB_HOST       = module.postgres.endpoint
    DB_PORT       = module.postgres.port
    DB_USER       = module.postgres.username
    DB_PASSWORD   = module.postgres.password
    CACHE_URL     = "redis://${module.redis.endpoint}:${module.redis.port}"
    ENVIRONMENT   = "production"
  }
}

output "api_function_arn" {
  value = module.score_workload.function_arn
}
```

### Score File Integration

```yaml
apiVersion: score.dev/v1b1
metadata:
  name: my-api

containers:
  api:
    image: 123456789.dkr.ecr.us-east-1.amazonaws.com/api:latest
    command: ["/app/bin/api"]
    args: ["--port", "9000"]
    variables:
      DB_HOST: ${resources.postgres.host}
      DB_PORT: ${resources.postgres.port}
      DB_USER: ${resources.postgres.username}
      DB_PASSWORD: ${resources.postgres.password}
      CACHE_URL: ${resources.redis.url}
      ENVIRONMENT: production
      LOG_LEVEL: info

resources:
  postgres:
    type: postgres
    params:
      version: "15"
      storage: 20Gi
  redis:
    type: redis
    params:
      version: "7.0"
```

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│ Humanitec Platform Orchestrator                         │
│ (Score Processing & Resource Orchestration)            │
└──────────────────────┬──────────────────────────────────┘
                       │
        ┌──────────────┼──────────────┐
        │              │              │
   Postgres Module   Redis Module   Lambda Module (this)
        │              │              │
        └──────────────┼──────────────┘
                       │
        ┌──────────────▼──────────────┐
        │ AWS Resources               │
        ├─────────────────────────────┤
        │ • RDS Postgres Instance     │
        │ • ElastiCache Redis         │
        │ • Lambda Function           │
        │ • IAM Execution Role        │
        │ • CloudWatch Log Group      │
        └─────────────────────────────┘
```

## Technical References

### Humanitec Documentation
- [Score Overview](https://developer.humanitec.com/platform-orchestrator/docs/score/overview/) - Score file structure and workload definition
- [Custom Resource Types](https://developer.humanitec.com/platform-orchestrator/docs/platform-orchestrator/resources/custom-resource-types/) - Extending and configuring resource types
- [Resource Definitions](https://developer.humanitec.com/platform-orchestrator/docs/platform-orchestrator/resources/resource-definitions/) - Mapping resources to drivers/modules

### AWS Documentation
- [AWS Lambda Containers](https://docs.aws.amazon.com/lambda/latest/dg/images-create.html) - Container image support in Lambda
- [Lambda Runtime Interface](https://docs.aws.amazon.com/lambda/latest/dg/runtimes-images.html) - Container runtime requirements
- [Lambda Execution Role](https://docs.aws.amazon.com/lambda/latest/dg/lambda-intro-execution-role.html) - IAM permissions for Lambda

### Terraform Documentation
- [AWS Lambda Resource](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lambda_function)
- [IAM Role & Policy Resources](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role)