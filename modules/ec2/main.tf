# Look up the latest Ubuntu 22.04 AMI instead of hardcoding an AMI ID.
# Why: AMI IDs are different per region and change over time as AWS
# releases patched images - hardcoding one means the code silently goes
# stale or breaks if you ever change region.
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical (official Ubuntu publisher)

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# --- Bastion security group ---
# Why: this is the ONLY thing on the internet that can SSH anywhere. It
# only accepts SSH, and only from your one IP - not the world.
#
# Rules are separate aws_security_group_rule resources below, not inline
# in this block - because the root config later adds a cross-module rule
# to this SG (allowing ping from VPC2 for the peering proof). An SG with
# inline rules treats itself as the full authoritative rule set and
# silently deletes anything added elsewhere on the next apply.
resource "aws_security_group" "bastion" {
  name        = "${var.name}-bastion-sg"
  description = "Allow SSH from my IP only"
  vpc_id      = var.vpc_id

  tags = {
    Name = "${var.name}-bastion-sg"
  }
}

resource "aws_security_group_rule" "bastion_ssh_in" {
  type              = "ingress"
  description       = "SSH from my IP"
  from_port         = 22
  to_port           = 22
  protocol          = "tcp"
  cidr_blocks       = [var.allowed_ssh_cidr]
  security_group_id = aws_security_group.bastion.id
}

resource "aws_security_group_rule" "bastion_egress_all" {
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.bastion.id
}

# --- Private (Cribl) instances security group ---
# Why: no rule here allows traffic from the internet. SSH is only allowed
# FROM the bastion's security group - not from any IP address. The ALB
# rule (allowing traffic on Cribl's port) gets added later, from the root
# config, to avoid these two modules needing to know about each other -
# same reasoning as above for why rules are standalone, not inline.
resource "aws_security_group" "private" {
  name        = "${var.name}-private-sg"
  description = "Cribl instances - SSH only from bastion"
  vpc_id      = var.vpc_id

  tags = {
    Name = "${var.name}-private-sg"
  }
}

resource "aws_security_group_rule" "private_ssh_from_bastion" {
  type                     = "ingress"
  description              = "SSH from bastion only"
  from_port                = 22
  to_port                  = 22
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.bastion.id
  security_group_id        = aws_security_group.private.id
}

resource "aws_security_group_rule" "private_egress_all" {
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"] # needed so instances can download Cribl
  security_group_id = aws_security_group.private.id
}

# --- Bastion host ---
resource "aws_instance" "bastion" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.bastion_instance_type
  subnet_id                   = var.public_subnet_id
  vpc_security_group_ids      = [aws_security_group.bastion.id]
  key_name                    = var.key_pair_name
  associate_public_ip_address = true

  tags = {
    Name = "${var.name}-bastion"
  }
}

# --- Cribl instances (private subnets) ---
# count spreads them across the private subnets round-robin, so with 2
# subnets and 3 instances you get 2 in one AZ and 1 in the other.
resource "aws_instance" "cribl" {
  count                  = var.instance_count
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  subnet_id              = var.private_subnet_ids[count.index % length(var.private_subnet_ids)]
  vpc_security_group_ids = [aws_security_group.private.id]
  key_name               = var.key_pair_name

  tags = {
    Name = "${var.name}-cribl-node-${count.index + 1}"
    Role = "cribl" # Ansible's dynamic inventory will group instances by this tag
  }
}
