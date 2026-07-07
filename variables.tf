variable "function_name" {
  description = "Name of the Lambda function"
  type        = string
  default     = "score-workload"
}

variable "containers" {
  description = "Map of container definitions from Score spec. Key is container name, value has image, command, args, and variables fields. When set, takes precedence over container_image/container_command/container_args."
  type = map(object({
    image     = string
    command   = optional(list(string))
    args      = optional(list(string))
    variables = optional(map(string), {})
  }))
  default = {}
}

variable "container_image" {
  description = "Container image URI from ECR or container registry (e.g., 123456789.dkr.ecr.us-east-1.amazonaws.com/my-app:v1.0.0). Ignored when containers var is set."
  type        = string
  default     = null
}

variable "container_command" {
  description = "Container command to execute (overrides ENTRYPOINT). Ignored when containers var is set."
  type        = list(string)
  default     = null
}

variable "container_args" {
  description = "Container arguments (overrides CMD). Ignored when containers var is set."
  type        = list(string)
  default     = null
}

variable "environment_variables" {
  description = "Environment variables passed to container (resolved resource outputs + custom variables). Merged with variables from the containers var."
  type        = map(string)
  default     = {}
}

variable "memory_size" {
  description = "Lambda memory allocation in MB (128-10240)"
  type        = number
  default     = 256

  validation {
    condition     = var.memory_size >= 128 && var.memory_size <= 10240
    error_message = "memory_size must be between 128 and 10240 MB."
  }
}

variable "service" {
  description = "Service name"
  type        = string
}

variable "timeout" {
  description = "Function timeout in seconds (1-900)"
  type        = number
  default     = 60

  validation {
    condition     = var.timeout >= 1 && var.timeout <= 900
    error_message = "timeout must be between 1 and 900 seconds."
  }
}

variable "ephemeral_storage_size" {
  description = "Ephemeral storage size in MB (512-10240)"
  type        = number
  default     = 512

  validation {
    condition     = var.ephemeral_storage_size >= 512 && var.ephemeral_storage_size <= 10240
    error_message = "ephemeral_storage_size must be between 512 and 10240 MB."
  }
}

variable "architectures" {
  description = "Lambda CPU architectures (x86_64 or arm64)"
  type        = list(string)
  default     = ["x86_64"]

  validation {
    condition     = alltrue([for arch in var.architectures : contains(["x86_64", "arm64"], arch)])
    error_message = "architectures must contain only 'x86_64' or 'arm64'."
  }
}

variable "log_retention_days" {
  description = "CloudWatch Log Group retention period in days (1-3653)"
  type        = number
  default     = 7

  validation {
    condition     = var.log_retention_days >= 1 && var.log_retention_days <= 3653
    error_message = "log_retention_days must be between 1 and 3653 days."
  }
}

variable "tags" {
  description = "Tags to apply to AWS resources"
  type        = map(string)
  default     = {}
}
