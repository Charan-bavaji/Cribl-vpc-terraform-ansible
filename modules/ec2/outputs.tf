output "bastion_public_ip" {
  value = aws_instance.bastion.public_ip
}

output "bastion_security_group_id" {
  value = aws_security_group.bastion.id
}

output "private_security_group_id" {
  description = "Used later by the ALB module to allow traffic from the ALB into these instances"
  value       = aws_security_group.private.id
}

output "cribl_instance_ids" {
  value = aws_instance.cribl[*].id
}

output "cribl_private_ips" {
  value = aws_instance.cribl[*].private_ip
}
