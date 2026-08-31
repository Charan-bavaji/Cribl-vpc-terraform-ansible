# Why variables instead of hardcoding values:
# - lets you reuse this same code for staging/prod later by just changing
#   terraform.tfvars, not the code itself
# - keeps CIDR ranges, region, etc. in one visible place instead of buried
#   inside module code

variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "ap-south-1"
}

variable "vpc1_cidr" {
  description = "CIDR block for VPC1 (the private/compute VPC)"
  type        = string
  default     = "10.0.0.0/16"
}

variable "vpc2_cidr" {
  description = "CIDR block for VPC2 (the public entry VPC). Must not overlap vpc1_cidr."
  type        = string
  default     = "10.1.0.0/16"
}

variable "instance_type" {
  description = "EC2 instance type for the Cribl nodes"
  type        = string
  default     = "t3.medium" # Cribl needs more than micro/small to run comfortably
}

variable "key_pair_name" {
  description = "Existing EC2 key pair name, used for SSH access (Ansible)"
  type        = string
}

variable "my_ip_cidr" {
  description = "Your public IP as a /32 CIDR - only this IP can SSH into the bastion"
  type        = string
}
