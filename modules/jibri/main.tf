# ECS-optimized Amazon Linux 2 AMI (latest)
data "aws_ssm_parameter" "ecs_ami" {
  name = "/aws/service/ecs/optimized-ami/amazon-linux-2/recommended/image_id"
}

# ── IAM: EC2 instance role for ECS container agent + S3 recordings ───────────

resource "aws_iam_role" "jibri_instance" {
  name = "${var.project_name}-jibri-instance-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })

  tags = {
    Name        = "${var.project_name}-jibri-instance-role"
    Project     = var.project_name
    Environment = var.environment
  }
}

resource "aws_iam_role_policy_attachment" "jibri_ecs_ec2" {
  role       = aws_iam_role.jibri_instance.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role"
}

resource "aws_iam_role_policy" "jibri_s3" {
  name = "${var.project_name}-jibri-s3"
  role = aws_iam_role.jibri_instance.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = ["s3:PutObject", "s3:ListBucket"]
      Resource = [
        "arn:aws:s3:::${var.recordings_bucket}",
        "arn:aws:s3:::${var.recordings_bucket}/*"
      ]
    }]
  })
}

resource "aws_iam_instance_profile" "jibri" {
  name = "${var.project_name}-jibri-instance-profile"
  role = aws_iam_role.jibri_instance.name
}

# ── Launch Template ───────────────────────────────────────────────────────────

resource "aws_launch_template" "jibri" {
  name_prefix   = "${var.project_name}-jibri-"
  image_id      = data.aws_ssm_parameter.ecs_ami.value
  instance_type = var.instance_type

  iam_instance_profile {
    arn = aws_iam_instance_profile.jibri.arn
  }

  vpc_security_group_ids = [var.security_group_id]

  # Register with ECS cluster; load snd-aloop for Jibri's virtual audio device.
  user_data = base64encode(<<-EOF
    #!/bin/bash
    echo ECS_CLUSTER=${var.cluster_name} >> /etc/ecs/ecs.config
    modprobe snd-aloop
    echo snd-aloop >> /etc/modules-load.d/snd-aloop.conf
  EOF
  )

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name        = "${var.project_name}-jibri"
      Project     = var.project_name
      Environment = var.environment
    }
  }
}

# ── Auto Scaling Group ────────────────────────────────────────────────────────

resource "aws_autoscaling_group" "jibri" {
  name                = "${var.project_name}-jibri-asg"
  min_size            = 0
  max_size            = var.jibri_count
  desired_capacity    = var.jibri_count
  vpc_zone_identifier = var.subnet_ids

  launch_template {
    id      = aws_launch_template.jibri.id
    version = "$Latest"
  }

  # Required so ECS can discover and drain instances.
  protect_from_scale_in = true

  tag {
    key                 = "AmazonECSManaged"
    value               = "true"
    propagate_at_launch = true
  }

  tag {
    key                 = "Project"
    value               = var.project_name
    propagate_at_launch = true
  }

  tag {
    key                 = "Environment"
    value               = var.environment
    propagate_at_launch = true
  }
}

# ── ECS Capacity Provider ─────────────────────────────────────────────────────
# NOTE for JIB-2: This module creates the capacity provider resource but does NOT
# call aws_ecs_cluster_capacity_providers. That resource is cluster-wide and would
# conflict if prod.tf ever manages it. JIB-2 should add the association in prod.tf:
#
#   resource "aws_ecs_cluster_capacity_providers" "main" {
#     cluster_name       = aws_ecs_cluster.main.name
#     capacity_providers = [module.jibri[0].capacity_provider_name]
#   }

resource "aws_ecs_capacity_provider" "jibri" {
  name = "${var.project_name}-jibri-cp"

  auto_scaling_group_provider {
    auto_scaling_group_arn         = aws_autoscaling_group.jibri.arn
    managed_termination_protection = "ENABLED"

    managed_scaling {
      status          = "ENABLED"
      target_capacity = 100
    }
  }

  tags = {
    Name        = "${var.project_name}-jibri-cp"
    Project     = var.project_name
    Environment = var.environment
  }
}

# ── ECS Task Definition ───────────────────────────────────────────────────────

resource "aws_ecs_task_definition" "jibri" {
  family                   = "${var.project_name}-jibri"
  requires_compatibilities = ["EC2"]
  network_mode             = "awsvpc"
  task_role_arn            = aws_iam_role.jibri_instance.arn
  execution_role_arn       = var.ecs_task_execution_role_arn

  volume {
    name      = "recordings"
    host_path = "/recordings"
  }

  container_definitions = jsonencode([{
    name      = "jibri"
    image     = "jitsi/jibri:stable"
    essential = true

    # Jibri requires a privileged container for snd-aloop and Chrome sandbox.
    privileged = true

    linuxParameters = {
      devices = [{
        hostPath      = "/dev/snd"
        containerPath = "/dev/snd"
        permissions   = ["read", "write"]
      }]
    }

    mountPoints = [{
      sourceVolume  = "recordings"
      containerPath = "/config/recordings"
    }]

    environment = [
      # XMPP_SERVER: resolved via Cloud Map DNS discovery of the jitsi ECS service.
      { name = "XMPP_SERVER", value = var.prosody_dns },
      { name = "XMPP_DOMAIN", value = "meet.jitsi" },
      { name = "XMPP_AUTH_DOMAIN", value = "auth.meet.jitsi" },
      { name = "XMPP_INTERNAL_MUC_DOMAIN", value = "internal-muc.meet.jitsi" },
      { name = "XMPP_RECORDER_DOMAIN", value = "recorder.meet.jitsi" },
      { name = "JIBRI_RECORDER_USER", value = "recorder" },
      { name = "JIBRI_XMPP_USER", value = "jibri" },
      { name = "JIBRI_BREWERY_MUC", value = "jibribrewery" },
      { name = "JIBRI_RECORDING_DIR", value = "/config/recordings" },
      { name = "JIBRI_FINALIZE_RECORDING_SCRIPT_PATH", value = "/config/finalize.sh" },
      { name = "RECORDINGS_BUCKET", value = var.recordings_bucket },
      { name = "DISPLAY", value = ":0" },
      { name = "TZ", value = "UTC" }
    ]

    secrets = [
      { name = "JIBRI_RECORDER_PASSWORD", valueFrom = var.jibri_recorder_password_ssm_arn },
      { name = "JIBRI_XMPP_PASSWORD", valueFrom = var.jibri_xmpp_password_ssm_arn }
    ]

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = var.log_group_name
        "awslogs-region"        = var.region
        "awslogs-stream-prefix" = "jibri"
      }
    }
  }])

  tags = {
    Name        = "${var.project_name}-jibri-td"
    Project     = var.project_name
    Environment = var.environment
  }
}

# ── ECS Service ───────────────────────────────────────────────────────────────

resource "aws_ecs_service" "jibri" {
  name            = "${var.project_name}-jibri-service"
  cluster         = var.cluster_id
  task_definition = aws_ecs_task_definition.jibri.arn
  desired_count   = var.jibri_count

  capacity_provider_strategy {
    capacity_provider = aws_ecs_capacity_provider.jibri.name
    weight            = 1
  }

  network_configuration {
    subnets         = var.subnet_ids
    security_groups = [var.security_group_id]
  }

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  tags = {
    Name        = "${var.project_name}-jibri-service"
    Project     = var.project_name
    Environment = var.environment
  }
}
