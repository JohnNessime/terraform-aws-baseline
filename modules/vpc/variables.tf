variable "name_prefix" {
  description = "Resource name prefix, conventionally module.tags.name_prefix (<project>-<environment>)."
  type        = string
}

variable "vpc_cidr" {
  description = "IPv4 CIDR block for the VPC. Use an RFC 1918 documentation range."
  type        = string

  validation {
    # cidrhost() throws on a malformed prefix, so `can()` turns a bad value into
    # a plan-time error instead of a confusing failure deep inside a for expression.
    condition     = can(cidrhost(var.vpc_cidr, 0))
    error_message = "vpc_cidr must be a valid IPv4 CIDR block (e.g. 10.0.0.0/16)."
  }

  validation {
    # A /16../24 leaves room to carve three tiers across the AZs below; anything
    # smaller than /24 cannot hold the subnet maths in main.tf.
    condition     = tonumber(split("/", var.vpc_cidr)[1]) <= 24
    error_message = "vpc_cidr prefix must be /24 or larger (a smaller number) to fit three subnet tiers."
  }
}

variable "az_count" {
  description = "Number of Availability Zones to span. Each tier gets one subnet per AZ."
  type        = number
  default     = 2

  validation {
    condition     = var.az_count >= 2 && var.az_count <= 3
    error_message = "az_count must be 2 or 3: two AZs is the multi-AZ minimum, three is the practical ceiling for this /16 subnet plan."
  }
}

variable "enable_nat_gateway" {
  description = "Provision NAT gateways so private subnets can reach the internet outbound."
  type        = bool
  default     = true
}

variable "single_nat_gateway" {
  description = "Use one shared NAT gateway instead of one per AZ. Cheaper, but a single-AZ failure severs private egress."
  type        = bool
  default     = false
}

variable "enable_flow_logs" {
  description = "Capture VPC Flow Logs to a KMS-encrypted CloudWatch log group."
  type        = bool
  default     = true
}

variable "flow_log_retention_days" {
  description = "Retention for the flow log group. Must be a value CloudWatch Logs accepts."
  type        = number
  default     = 90

  validation {
    condition = contains(
      [1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653],
      var.flow_log_retention_days
    )
    error_message = "flow_log_retention_days must be one of the retention periods CloudWatch Logs supports (e.g. 7, 30, 90, 365)."
  }
}
