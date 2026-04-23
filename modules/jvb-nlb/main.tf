# Network Load Balancer for JVB UDP traffic
resource "aws_lb" "jvb" {
  name               = "${var.project_name}-jvb-nlb"
  internal           = false
  load_balancer_type = "network"
  subnets            = var.subnet_ids

  enable_deletion_protection = false

  tags = {
    Name        = "${var.project_name}-jvb-nlb"
    Project     = var.project_name
    Environment = var.environment
  }
}

# Target Group for JVB UDP traffic
resource "aws_lb_target_group" "jvb_udp" {
  name        = "${var.project_name}-jvb-udp-tg"
  port        = 10000
  protocol    = "UDP"
  vpc_id      = var.vpc_id
  target_type = "ip"

  health_check {
    enabled             = true
    healthy_threshold   = 2
    interval            = 30
    matcher             = "200"
    path                = "/about/health"
    port                = "8080"
    protocol            = "HTTP"
    timeout             = 5
    unhealthy_threshold = 2
  }

  tags = {
    Name        = "${var.project_name}-jvb-udp-tg"
    Project     = var.project_name
    Environment = var.environment
  }
}

# Target Group for JVB TCP fallback
resource "aws_lb_target_group" "jvb_tcp" {
  name        = "${var.project_name}-jvb-tcp-tg"
  port        = 4443
  protocol    = "TCP"
  vpc_id      = var.vpc_id
  target_type = "ip"

  health_check {
    enabled             = true
    healthy_threshold   = 2
    interval            = 30
    # jvb on :8080 serves /about/health; / returns 404 and fails HC.
    path                = "/about/health"
    port                = "8080"
    protocol            = "HTTP"
    timeout             = 5
    unhealthy_threshold = 2
  }

  tags = {
    Name        = "${var.project_name}-jvb-tcp-tg"
    Project     = var.project_name
    Environment = var.environment
  }
}

# Listener for UDP traffic
resource "aws_lb_listener" "jvb_udp" {
  load_balancer_arn = aws_lb.jvb.arn
  port              = "10000"
  protocol          = "UDP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.jvb_udp.arn
  }
}

# Listener for TCP fallback
resource "aws_lb_listener" "jvb_tcp" {
  load_balancer_arn = aws_lb.jvb.arn
  port              = "4443"
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.jvb_tcp.arn
  }
}
