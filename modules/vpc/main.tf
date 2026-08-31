# The VPC itself.
resource "aws_vpc" "this" {
  cidr_block           = var.cidr_block
  enable_dns_support   = true
  enable_dns_hostnames = true # required for ALB and any public DNS name resolution

  tags = {
    Name = "${var.name}-vpc"
  }
}

# Public subnets - one per AZ. These will hold the ALB (and, for VPC2,
# whatever public-facing entry resource sits there).
resource "aws_subnet" "public" {
  count                   = length(var.public_subnet_cidrs)
  vpc_id                  = aws_vpc.this.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = var.azs[count.index]
  map_public_ip_on_launch = true # instances here get a public IP automatically

  tags = {
    Name = "${var.name}-public-${count.index + 1}"
  }
}

# Private subnets - one per AZ. These will hold the EC2 instances running
# Cribl. No public IPs here - traffic reaches them only through the ALB.
resource "aws_subnet" "private" {
  count             = length(var.private_subnet_cidrs)
  vpc_id             = aws_vpc.this.id
  cidr_block         = var.private_subnet_cidrs[count.index]
  availability_zone  = var.azs[count.index]

  tags = {
    Name = "${var.name}-private-${count.index + 1}"
  }
}

# Internet Gateway - lets public subnets reach/be reached from the internet.
resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = {
    Name = "${var.name}-igw"
  }
}

# Route table for public subnets. Routes are added as SEPARATE aws_route
# resources below (not inline here) - mixing inline "route {}" blocks
# with standalone aws_route resources on the same table causes Terraform
# to treat the inline block as the full authoritative list and silently
# delete any route added separately (like the peering route added from
# the root config) on the next apply.
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  tags = {
    Name = "${var.name}-public-rt"
  }
}

resource "aws_route" "public_igw" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id              = aws_internet_gateway.this.id
}

resource "aws_route_table_association" "public" {
  count          = length(aws_subnet.public)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# --- NAT Gateway: gives private subnets outbound-only internet access ---
# Why: instances in the private subnets (the Cribl nodes) need to reach
# the internet to download the Cribl package - but must stay unreachable
# FROM the internet, which is the whole point of a private subnet. A NAT
# Gateway does exactly that: outbound only, nothing can initiate a
# connection back in. It needs to sit in a PUBLIC subnet itself, since it
# needs its own route to the Internet Gateway.
resource "aws_eip" "nat" {
  count  = length(var.private_subnet_cidrs) > 0 ? 1 : 0
  domain = "vpc"

  tags = {
    Name = "${var.name}-nat-eip"
  }
}

resource "aws_nat_gateway" "this" {
  count         = length(var.private_subnet_cidrs) > 0 ? 1 : 0
  allocation_id = aws_eip.nat[0].id
  subnet_id     = aws_subnet.public[0].id

  tags = {
    Name = "${var.name}-nat"
  }

  depends_on = [aws_internet_gateway.this]
}

# Private route table exists so we can add the VPC-peering route to it later,
# without touching the public route table.
resource "aws_route_table" "private" {
  count  = length(var.private_subnet_cidrs) > 0 ? 1 : 0
  vpc_id = aws_vpc.this.id

  tags = {
    Name = "${var.name}-private-rt"
  }
}

resource "aws_route" "private_nat" {
  count                  = length(var.private_subnet_cidrs) > 0 ? 1 : 0
  route_table_id          = aws_route_table.private[0].id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id          = aws_nat_gateway.this[0].id
}

resource "aws_route_table_association" "private" {
  count          = length(aws_subnet.private)
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private[0].id
}

# --- Network ACL: public subnets (bastion + ALB) ---
# Why explicit rules and not "allow all": a NACL is a second, subnet-wide
# layer that still blocks traffic even if a security group is ever
# misconfigured. Only opening the ports actually needed (SSH from admin,
# HTTP/HTTPS for the ALB, plus the ephemeral range for return traffic)
# keeps that protection meaningful instead of just rubber-stamping.
#
# NACLs are stateless - unlike security groups, a reply to an allowed
# request is NOT automatically allowed back in. The ephemeral port rule
# (1024-65535) exists specifically to let that return traffic through.
resource "aws_network_acl" "public" {
  vpc_id     = aws_vpc.this.id
  subnet_ids = aws_subnet.public[*].id

  tags = {
    Name = "${var.name}-public-nacl"
  }
}

# Rules are separate resources (not inline in the block above) for the
# same reason routes are: an aws_network_acl with inline ingress/egress
# blocks treats itself as the FULL authoritative rule list, and silently
# deletes any rule added elsewhere (like the peering ICMP rules added
# from the root config) on the next apply. Standalone resources avoid
# that fight entirely.
resource "aws_network_acl_rule" "public_ssh" {
  network_acl_id = aws_network_acl.public.id
  rule_number    = 100
  egress         = false
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = var.allowed_ssh_cidr
  from_port      = 22
  to_port        = 22
}

resource "aws_network_acl_rule" "public_http" {
  network_acl_id = aws_network_acl.public.id
  rule_number    = 110
  egress         = false
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = "0.0.0.0/0"
  from_port      = 80
  to_port        = 80
}

resource "aws_network_acl_rule" "public_https" {
  network_acl_id = aws_network_acl.public.id
  rule_number    = 120
  egress         = false
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = "0.0.0.0/0"
  from_port      = 443
  to_port        = 443
}

resource "aws_network_acl_rule" "public_ephemeral_in" {
  network_acl_id = aws_network_acl.public.id
  rule_number    = 130
  egress         = false
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = "0.0.0.0/0"
  from_port      = 1024
  to_port        = 65535
}

# Outbound left open: the public subnet's own security groups (bastion,
# ALB) already scope what's actually reachable per-instance. The NACL's
# job here is guarding what's allowed IN from the internet.
resource "aws_network_acl_rule" "public_egress_all" {
  network_acl_id = aws_network_acl.public.id
  rule_number    = 100
  egress         = true
  protocol       = "-1"
  rule_action    = "allow"
  cidr_block     = "0.0.0.0/0"
  from_port      = 0
  to_port        = 0
}

# --- Network ACL: private subnets (Cribl instances) ---
# Only allows SSH from the public subnets (where the bastion lives) and
# the app port from the public subnets (where the ALB lives) - nothing
# from the open internet at all, even before security groups are checked.
resource "aws_network_acl" "private" {
  count      = length(var.private_subnet_cidrs) > 0 ? 1 : 0
  vpc_id     = aws_vpc.this.id
  subnet_ids = aws_subnet.private[*].id

  tags = {
    Name = "${var.name}-private-nacl"
  }
}

resource "aws_network_acl_rule" "private_ssh" {
  for_each        = length(var.private_subnet_cidrs) > 0 ? { for idx, cidr in var.public_subnet_cidrs : idx => cidr } : {}
  network_acl_id  = aws_network_acl.private[0].id
  rule_number     = 100 + tonumber(each.key)
  egress          = false
  protocol        = "tcp"
  rule_action     = "allow"
  cidr_block      = each.value
  from_port       = 22
  to_port         = 22
}

resource "aws_network_acl_rule" "private_app_port" {
  for_each        = length(var.private_subnet_cidrs) > 0 ? { for idx, cidr in var.public_subnet_cidrs : idx => cidr } : {}
  network_acl_id  = aws_network_acl.private[0].id
  rule_number     = 200 + tonumber(each.key)
  egress          = false
  protocol        = "tcp"
  rule_action     = "allow"
  cidr_block      = each.value
  from_port       = var.app_port
  to_port         = var.app_port
}

resource "aws_network_acl_rule" "private_ephemeral_in" {
  count           = length(var.private_subnet_cidrs) > 0 ? 1 : 0
  network_acl_id  = aws_network_acl.private[0].id
  rule_number     = 300
  egress          = false
  protocol        = "tcp"
  rule_action     = "allow"
  cidr_block      = "0.0.0.0/0"
  from_port       = 1024
  to_port         = 65535
}

# Outbound open: instances need this to download Cribl (HTTPS out),
# resolve DNS, and reply to the ALB/bastion. Security groups still
# scope per-instance what's actually listening.
resource "aws_network_acl_rule" "private_egress_all" {
  count           = length(var.private_subnet_cidrs) > 0 ? 1 : 0
  network_acl_id  = aws_network_acl.private[0].id
  rule_number     = 100
  egress          = true
  protocol        = "-1"
  rule_action     = "allow"
  cidr_block      = "0.0.0.0/0"
  from_port       = 0
  to_port         = 0
}
