# VPC1: the private/compute VPC. Holds the EC2 instances, ALB, Route 53.
module "vpc1" {
  source = "../../modules/vpc"

  name       = "vpc1"
  cidr_block = var.vpc1_cidr

  # /24 subnets inside the /16 VPC CIDR - gives 256 IPs per subnet, plenty
  # for this project.
  public_subnet_cidrs  = ["10.0.1.0/24", "10.0.2.0/24"]
  private_subnet_cidrs = ["10.0.11.0/24", "10.0.12.0/24"]
  allowed_ssh_cidr     = var.my_ip_cidr
}

# Bastion host (in VPC1's public subnet) + 3 Cribl instances (private subnets).
module "ec2" {
  source = "../../modules/ec2"

  name                = "cribl"
  vpc_id              = module.vpc1.vpc_id
  public_subnet_id    = module.vpc1.public_subnet_ids[0]
  private_subnet_ids  = module.vpc1.private_subnet_ids
  key_pair_name       = var.key_pair_name
  allowed_ssh_cidr    = var.my_ip_cidr
  instance_type       = var.instance_type
  instance_count      = 3
}

# ALB in front of the 3 Cribl instances.
module "alb" {
  source = "../../modules/alb"

  name              = "cribl"
  vpc_id            = module.vpc1.vpc_id
  public_subnet_ids = module.vpc1.public_subnet_ids
  instance_ids      = module.ec2.cribl_instance_ids
  app_port          = 9000
}

# The rule that actually lets the ALB reach the Cribl instances - added
# here (not inside either module) so the EC2 and ALB modules don't need
# to directly depend on each other.
resource "aws_security_group_rule" "alb_to_cribl" {
  type                     = "ingress"
  from_port                = 9000
  to_port                  = 9000
  protocol                 = "tcp"
  security_group_id        = module.ec2.private_security_group_id
  source_security_group_id = module.alb.alb_security_group_id
  description               = "Allow ALB to reach Cribl instances on their app port"
}

# --- VPC2: exists purely to demonstrate peering, not as a public entry
# point (VPC peering can't proxy public traffic between VPCs - see
# discussion). One public subnet, no NAT/private subnets needed.
module "vpc2" {
  source = "../../modules/vpc"

  name                 = "vpc2"
  cidr_block           = var.vpc2_cidr
  public_subnet_cidrs  = ["10.1.1.0/24"]
  private_subnet_cidrs = []
  allowed_ssh_cidr     = var.my_ip_cidr
}

# Small test instance in VPC2, used only to prove the peering connection
# actually routes traffic - not part of the Cribl application itself.
resource "aws_security_group" "vpc2_test" {
  name        = "vpc2-test-sg"
  description = "SSH from my IP, all outbound (for testing peered connectivity)"
  vpc_id      = module.vpc2.vpc_id

  ingress {
    description = "SSH from my IP"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.my_ip_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "vpc2-test-sg"
  }
}

data "aws_ami" "vpc2_ubuntu" {
  most_recent = true
  owners      = ["099720109477"]

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }
}

resource "aws_instance" "vpc2_test" {
  ami                         = data.aws_ami.vpc2_ubuntu.id
  instance_type               = "t3.micro"
  subnet_id                   = module.vpc2.public_subnet_ids[0]
  vpc_security_group_ids      = [aws_security_group.vpc2_test.id]
  key_name                    = var.key_pair_name
  associate_public_ip_address = true

  tags = {
    Name = "vpc2-test-instance"
  }
}

# --- Peering: connects VPC1 and VPC2's private IP space directly.
module "peering" {
  source = "../../modules/peering"

  requester_vpc_id = module.vpc1.vpc_id
  accepter_vpc_id  = module.vpc2.vpc_id
  requester_cidr   = var.vpc1_cidr
  accepter_cidr    = var.vpc2_cidr

  requester_route_table_ids = [
    module.vpc1.public_route_table_id,
    module.vpc1.private_route_table_id,
  ]
  accepter_route_table_ids = [module.vpc2.public_route_table_id]
}

# --- Peering proof: allow ONLY ping (ICMP) from VPC2 into the bastion.
# Deliberately narrow - this exists to prove the peering connection
# actually carries traffic, not to open up real access between the VPCs.
resource "aws_security_group_rule" "vpc2_ping_bastion" {
  type              = "ingress"
  protocol          = "icmp"
  from_port         = 8 # echo request
  to_port           = 0
  cidr_blocks       = [var.vpc2_cidr]
  security_group_id = module.ec2.bastion_security_group_id
  description       = "Peering proof: allow ping from VPC2 test instance"
}

resource "aws_network_acl_rule" "vpc1_public_allow_icmp_from_vpc2" {
  network_acl_id = module.vpc1.public_nacl_id
  rule_number    = 140
  egress         = false
  protocol       = "icmp"
  rule_action    = "allow"
  cidr_block     = var.vpc2_cidr
  icmp_type      = 8
  icmp_code      = -1
}

resource "aws_network_acl_rule" "vpc2_public_allow_icmp_reply_from_vpc1" { 
  network_acl_id = module.vpc2.public_nacl_id 
  rule_number = 140 
  egress = false 
  protocol = "icmp" 
  rule_action = "allow" 
  cidr_block = var.vpc1_cidr 
  icmp_type = 0 
  icmp_code = -1
}
