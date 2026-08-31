variable "requester_vpc_id" {
  type = string
}

variable "accepter_vpc_id" {
  type = string
}

variable "requester_cidr" {
  type = string
}

variable "accepter_cidr" {
  type = string
}

variable "requester_route_table_ids" {
  description = "Route tables on the requester side (VPC1) that need a route to the accepter's CIDR"
  type        = list(string)
}

variable "accepter_route_table_ids" {
  description = "Route tables on the accepter side (VPC2) that need a route to the requester's CIDR"
  type        = list(string)
}
