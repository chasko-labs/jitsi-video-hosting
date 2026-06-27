# ─── coturn ECS Fargate module ────────────────────────────────────────────────
#
# RELAY PORT RANGE — THE CENTRAL HARD PROBLEM
# ─────────────────────────────────────────────
# coturn's TURN relay allocates one UDP port per concurrent session from
# relay_min_port..relay_max_port. NLB cannot forward an arbitrary port range
# with a single listener; it requires one listener per port.
#
# Three options:
#   (a) NLB with one listener per relay port — verbose, expensive at scale,
#       hits NLB listener limits (max 50 per NLB) for any meaningful range.
#   (b) No NLB — Fargate task with assign_public_ip=true, SG opens the relay
#       range directly. Task ENI gets a public IP; coturn binds to it.
#       Tradeoff: public IP changes on redeploy (update DNS A record).
#   (c) EC2 with static Elastic IP — simplest IP management, loses Fargate.
#
# DECISION: option (b). coturn is a single-instance, stateless forwarder.
# No NLB is needed. The SG opens 3478/udp+tcp, 5349/tcp, and the relay UDP
# range. On redeploy, update turn.clouddelnorte.org → new ENI public IP.
# ──────────────────────────────────────────────────────────────────────────────

locals {
  name_prefix = "${var.project_name}-coturn-${var.environment}"
}

# ── Security Group ────────────────────────────────────────────────────────────
resource "aws_security_group" "coturn" {
  name        = "${local.name_prefix}-sg"
  description = "coturn STUN/TURN/TURNS — no NLB, direct public ENI"
  vpc_id      = var.vpc_id

  # STUN/TURN plaintext
  ingress {
    from_port   = 3478
    to_port     = 3478
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = 3478
    to_port     = 3478
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # TURNS over TLS (5349/tcp survives DPI / GFW HTTPS inspection)
  ingress {
    from_port   = 5349
    to_port     = 5349
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Relay UDP range — keep small (default 41 ports ≈ 10 concurrent sessions)
  ingress {
    from_port   = var.relay_min_port
    to_port     = var.relay_max_port
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${local.name_prefix}-sg" }
}

# ── IAM inline policy — allow execution role to read TLS cert + auth secret ──
resource "aws_iam_role_policy" "coturn_secrets" {
  name = "${local.name_prefix}-secrets"
  role = split("/", var.ecs_task_execution_role_arn)[1]

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["secretsmanager:GetSecretValue"]
        Resource = var.turn_cert_secret_arn
      },
      {
        Effect   = "Allow"
        Action   = ["ssm:GetParameter", "ssm:GetParameters"]
        Resource = var.turn_static_auth_secret_ssm_arn
      }
    ]
  })
}

# ── Task Definition ───────────────────────────────────────────────────────────
resource "aws_ecs_task_definition" "coturn" {
  family                   = "${local.name_prefix}-td"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = tostring(var.task_cpu)
  memory                   = tostring(var.task_memory)
  execution_role_arn       = var.ecs_task_execution_role_arn

  container_definitions = jsonencode([{
    name      = "coturn"
    image     = var.coturn_image
    essential = true

    # entrypoint.sh is embedded via a base64-encoded command override so we
    # don't need a custom image build. The shell script is written inline.
    # NOTE: if you prefer a custom image, bake entrypoint.sh into it and
    # remove the command override below.
    entryPoint = ["/bin/sh", "-c"]
    command    = [file("${path.module}/entrypoint.sh")]

    portMappings = [
      { containerPort = 3478, protocol = "udp" },
      { containerPort = 3478, protocol = "tcp" },
      { containerPort = 5349, protocol = "tcp" }
    ]

    environment = [
      { name = "TURN_REALM", value = var.turn_realm },
      { name = "RELAY_MIN_PORT", value = tostring(var.relay_min_port) },
      { name = "RELAY_MAX_PORT", value = tostring(var.relay_max_port) }
    ]

    # ECS injects Secrets Manager JSON key selectors with :key:: suffix syntax.
    # Secret must be a JSON object: {"cert": "<PEM>", "pkey": "<PEM>"}
    secrets = [
      { name = "TURN_TLS_CERT_PEM", valueFrom = "${var.turn_cert_secret_arn}:cert::" },
      { name = "TURN_TLS_PKEY_PEM", valueFrom = "${var.turn_cert_secret_arn}:pkey::" },
      { name = "TURN_STATIC_AUTH_SECRET", valueFrom = var.turn_static_auth_secret_ssm_arn }
    ]

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = var.log_group_name
        "awslogs-region"        = var.region
        "awslogs-stream-prefix" = "coturn"
      }
    }
  }])

  tags = { Name = "${local.name_prefix}-td" }

  depends_on = [aws_iam_role_policy.coturn_secrets]
}

# ── ECS Service (no NLB — direct public ENI, option b) ───────────────────────
resource "aws_ecs_service" "coturn" {
  name            = "${local.name_prefix}-svc"
  cluster         = var.cluster_id
  task_definition = aws_ecs_task_definition.coturn.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = var.subnet_ids
    security_groups  = [aws_security_group.coturn.id]
    assign_public_ip = true # ENI gets a public IP; coturn binds to it via external-ip discovery
  }

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  tags = { Name = "${local.name_prefix}-svc" }
}
