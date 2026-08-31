variable "name" {
  description = "Name prefix for these resources"
  type        = string
}

variable "vpc_id" {
  type = string
}

variable "public_subnet_id" {
  description = "Subnet the bastion host lives in - must be a public subnet"
  type        = string
}

variable "private_subnet_ids" {
  description = "Subnets the Cribl instances live in - must be private subnets"
  type        = list(string)
}

variable "key_pair_name" {
  type = string
}

variable "allowed_ssh_cidr" {
  description = "Your IP, as a /32 CIDR - only this address can SSH into the bastion"
  type        = string
}

variable "instance_type" {
  type    = string
  default = "t3.medium"
}

variable "bastion_instance_type" {
  description = "Bastion just relays SSH - doesn't need much power"
  type        = string
  default     = "t3.micro"
}

variable "instance_count" {
  description = "How many Cribl instances to launch"
  type        = number
  default     = 3
}
