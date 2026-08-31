output "vpc1_id" {
  value = module.vpc1.vpc_id
}

output "vpc1_public_subnet_ids" {
  value = module.vpc1.public_subnet_ids
}

output "vpc1_private_subnet_ids" {
  value = module.vpc1.private_subnet_ids
}

output "bastion_public_ip" {
  value = module.ec2.bastion_public_ip
}

output "cribl_private_ips" {
  value = module.ec2.cribl_private_ips
}

output "alb_dns_name" {
  description = "Hit this URL in a browser to reach Cribl through the load balancer"
  value       = module.alb.alb_dns_name
}

output "vpc2_test_instance_public_ip" {
  description = "SSH here to test peered connectivity into VPC1"
  value       = aws_instance.vpc2_test.public_ip
}
