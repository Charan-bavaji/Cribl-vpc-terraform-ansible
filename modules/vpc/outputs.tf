# Outputs let the root config (environments/dev) and other modules
# (ALB, EC2, peering) use this VPC's IDs without repeating lookups.

output "vpc_id" {
  value = aws_vpc.this.id
}

output "vpc_cidr" {
  value = aws_vpc.this.cidr_block
}

output "public_subnet_ids" {
  value = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  value = aws_subnet.private[*].id
}

output "private_route_table_id" {
  description = "Used later to inject the VPC-peering route"
  value       = length(aws_route_table.private) > 0 ? aws_route_table.private[0].id : null
}

output "public_route_table_id" {
  value = aws_route_table.public.id
}

output "public_nacl_id" {
  value = aws_network_acl.public.id
}
