variable "name" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "public_subnet_ids" {
  description = "ALB must sit in public subnets to accept internet traffic"
  type        = list(string)
}

variable "instance_ids" {
  description = "The Cribl EC2 instance IDs to register as ALB targets"
  type        = list(string)
}

variable "app_port" {
  description = "Port Cribl actually listens on"
  type        = number
  default     = 9000
}
