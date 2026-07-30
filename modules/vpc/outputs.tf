output "vpc_id" {
  description = "ID of the VPC."
  value       = aws_vpc.this.id
}

output "vpc_cidr_block" {
  description = "CIDR block of the VPC."
  value       = aws_vpc.this.cidr_block
}

output "public_subnet_ids" {
  description = "IDs of the public (internet-facing) subnets, keyed by AZ."
  value       = { for az, s in aws_subnet.public : az => s.id }
}

output "private_subnet_ids" {
  description = "IDs of the private (NAT-egress) subnets, keyed by AZ."
  value       = { for az, s in aws_subnet.private : az => s.id }
}

output "database_subnet_ids" {
  description = "IDs of the isolated database subnets (no internet route), keyed by AZ."
  value       = { for az, s in aws_subnet.database : az => s.id }
}

output "nat_gateway_ids" {
  description = "IDs of the provisioned NAT gateways, keyed by AZ. Empty when NAT is disabled."
  value       = { for az, n in aws_nat_gateway.this : az => n.id }
}

output "flow_log_group_name" {
  description = "Name of the CloudWatch log group receiving VPC flow logs, or null when disabled."
  value       = var.enable_flow_logs ? aws_cloudwatch_log_group.flow_log[0].name : null
}
