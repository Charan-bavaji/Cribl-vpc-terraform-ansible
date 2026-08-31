# ALB's own security group - the ONLY thing allowed to accept traffic
# from the open internet on port 80. The Cribl instances never get their
# own security group opened to 0.0.0.0/0 - only to this SG specifically
# (that rule is added from the root config, connecting this module to
# the EC2 module's private security group).
resource "aws_security_group" "alb" {
  name        = "${var.name}-alb-sg"
  description = "Allow HTTP from the internet"
  vpc_id      = var.vpc_id

  ingress {
    description = "HTTP from anywhere"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.name}-alb-sg"
  }
}

resource "aws_lb" "this" {
  name               = "${var.name}-alb"
  internal           = false # public-facing - this is the internet entry point
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = var.public_subnet_ids

  tags = {
    Name = "${var.name}-alb"
  }
}

resource "aws_lb_target_group" "cribl" {
  name     = "${var.name}-tg"
  port     = var.app_port
  protocol = "HTTP"
  vpc_id   = var.vpc_id

  # Health check: the ALB only sends traffic to instances that pass this.
  # Without it, a crashed Cribl instance would keep silently getting
  # traffic until someone noticed manually.
  health_check {
    path                = "/"
    protocol            = "HTTP"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    timeout             = 5
    interval            = 15
    matcher             = "200-399"
  }

  tags = {
    Name = "${var.name}-tg"
  }
}

# Register each Cribl instance as a target.
resource "aws_lb_target_group_attachment" "cribl" {
  count            = length(var.instance_ids)
  target_group_arn = aws_lb_target_group.cribl.arn
  target_id        = var.instance_ids[count.index]
  port             = var.app_port
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.this.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.cribl.arn
  }
}
