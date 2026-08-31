variable "name" {
  description = "Name prefix for this VPC's resources, e.g. vpc1 or vpc2"
  type        = string
}

variable "cidr_block" {
  description = "CIDR block for this VPC"
  type        = string
}

variable "azs" {
  description = "Availability zones to spread subnets across"
  type        = list(string)
  default     = ["ap-south-1a", "ap-south-1b"]
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets, one per AZ"
  type        = list(string)
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets, one per AZ. Leave empty list if this VPC needs no private subnets."
  type        = list(string)
  default     = []
}

variable "allowed_ssh_cidr" {
  description = "Your IP as a /32 CIDR - the only address the NACL allows SSH from, into the public subnets"
  type        = string
}

variable "app_port" {
  description = "Port the private instances actually serve on (Cribl UI/API) - NACL allows this from the public subnets (where the ALB lives)"
  type        = number
  default     = 9000
}
