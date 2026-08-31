output "alb_dns_name" {
  value = aws_lb.this.dns_name
}

output "alb_zone_id" {
  description = "Needed for Route 53's alias record later"
  value       = aws_lb.this.zone_id
}

output "alb_security_group_id" {
  value = aws_security_group.alb.id
}
