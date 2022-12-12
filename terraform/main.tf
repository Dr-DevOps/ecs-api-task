## IAM Policies and Roles ##
locals {
  account_id = data.aws_caller_identity.current.account_id
}

# resource "aws_iam_role" "ecs_task_execution_role" {
#   name = "replace-word-ecsTaskExecutionRole"
 
#   assume_role_policy = <<EOF
# {
#  "Version": "2012-10-17",
#  "Statement": [
#    {
#      "Action": "sts:AssumeRole",
#      "Principal": {
#        "Service": "ecs-tasks.amazonaws.com"
#      },
#      "Effect": "Allow",
#      "Sid": ""
#    }
#  ]
# }
# EOF
# }
 
# resource "aws_iam_role_policy_attachment" "ecs-task-execution-role-policy-attachment" {
#   role       = aws_iam_role.ecs_task_execution_role.name
#   policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
# }

resource "aws_iam_role" "ecs_service_role" {
  name               = "ecs_service_role"
  path               = "/"
  assume_role_policy = data.aws_iam_policy_document.ecs_service_role_pd.json

  inline_policy {
    name = "ecs-service"

    policy = jsonencode({
      Version = "2012-10-17"
      Statement = [
        {
          Action = [
            "elasticloadbalancing:DeregisterInstancesFromLoadBalancer",
            "elasticloadbalancing:DeregisterTargets",
            "elasticloadbalancing:Describe*",
            "elasticloadbalancing:RegisterInstancesWithLoadBalancer",
            "elasticloadbalancing:RegisterTargets",
            "ec2:Describe*",
            "ec2:AuthorizeSecurityGroupIngress",
            "ecs:*"
          ]
          Effect   = "Allow"
          Resource = "*"
        }
      ]
    })
  }
}

resource "aws_iam_role" "ec2_role" {
  name                = "ec2_role"
  path                = "/"
  assume_role_policy  = data.aws_iam_policy_document.ec2_role_pd.json
  managed_policy_arns = ["arn:aws:iam::aws:policy/service-role/AmazonEC2RoleforSSM"]

  inline_policy {
    name = "ecs-service"

    policy = jsonencode({
      Version = "2012-10-17"
      Statement = [
        {
          Action = [
            "ec2:DescribeTags",
            "ecs:CreateCluster",
            "ecs:DeregisterContainerInstance",
            "ecs:DiscoverPollEndpoint",
            "ecs:Poll",
            "ecs:RegisterContainerInstance",
            "ecs:StartTelemetrySession",
            "ecs:UpdateContainerInstancesState",
            "ecs:Submit*"
          ]
          Effect   = "Allow"
          Resource = "*"
        }
      ]
    })
  }

  inline_policy {
    name = "clogs-access"

    policy = jsonencode({
      Version = "2012-10-17"
      Statement = [
        {
          Action = [
            "logs:CreateLogStream",
            "logs:PutLogEvents",
          ]
          Effect = "Allow"
          Resource = [
            "arn:aws:logs:us-west-1:${local.account_id}:*/*",
          ]
        }
      ]
    })
  }

  inline_policy {
    name = "ecr-access"

    policy = jsonencode({
      Version = "2012-10-17"
      Statement = [
        {
          Action = [
            "ecr:BatchCheckLayerAvailability",
            "ecr:BatchGetImage",
            "ecr:GetDownloadUrlForLayer",
            "ecr:GetAuthorizationToken"
          ]
          Effect   = "Allow"
          Resource = "*"
        }
      ]
    })
  }
}


# Create a CloudWatch log group.
resource "aws_cloudwatch_log_group" "ecs_logs" {
  name              = "ecs-logs"
  retention_in_days = 14
}


#
resource "aws_iam_role" "ecs_task_execution_role" {
  name = "replace-word-ecsTaskExecutionRole"
 
  assume_role_policy = <<EOF
{
 "Version": "2012-10-17",
 "Statement": [
   {
     "Action": "sts:AssumeRole",
     "Principal": {
       "Service": "ecs-tasks.amazonaws.com"
     },
     "Effect": "Allow",
     "Sid": ""
   }
 ]
}
EOF
}
 
resource "aws_iam_role_policy_attachment" "ecs-task-execution-role-policy-attachment" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}




# Create an ECS task definition.
resource "aws_ecs_task_definition" "ecs_task_definition" {
  family                = "${var.service_name}-ecs-replace-word-app"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = 256
  memory                   = 512 
  execution_role_arn = aws_iam_role.ecs_task_execution_role.arn
  container_definitions = <<DEFINITION
[
  {
    "name": "replace-word-app",
    "cpu": 1,
    "image": "${var.ecs_image_url}",
    "essential": true,
    "memory": 1,
    "logConfiguration": {
      "logDriver": "awslogs",
      "options": {
        "awslogs-group": "ecs-logs",
        "awslogs-region": "us-west-1",
        "awslogs-stream-prefix": "ecs-replace-word-app"
      }
    },
    "portMappings": [
      {
        "containerPort": 5000
      }
    ]
  }
]
DEFINITION
}

# Create the Application Load Balancer.
resource "aws_lb" "main" {
  name                       = "ecsalb"
  internal                   = false
  load_balancer_type         = "application"
  security_groups            = [aws_security_group.ecs_sg.id]
  subnets                    = [aws_subnet.public_1.id, aws_subnet.public_2.id]
  idle_timeout               = 30
  enable_deletion_protection = false
}

# Create the ALB target group.
resource "aws_lb_target_group" "ecs_rest_api_tg" {
  name     = "ecs-tg"
  port     = 5000
  protocol = "HTTP"
  target_type = "ip"
  vpc_id   = aws_vpc.main.id
  health_check {
    path                = "/"
    protocol            = "HTTP"
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 2
    interval            = 10
    matcher             = "200-399"
  }
}

# Create the ALB listener.
resource "aws_lb_listener" "alb_listener" {
  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"
  default_action {
    target_group_arn = aws_lb_target_group.ecs_rest_api_tg.arn
    type             = "forward"
  }
}

# Create the ECS cluster.
resource "aws_ecs_cluster" "ecs_cluster" {
  name = "ecs_cluster"
}

# Create the ECS service.
resource "aws_ecs_service" "service" {
  name            = var.service_name
  cluster         = aws_ecs_cluster.ecs_cluster.id
  task_definition = aws_ecs_task_definition.ecs_task_definition.arn
  desired_count   = var.desired_capacity
  #iam_role        = aws_iam_role.ecs_service_role.arn
  force_new_deployment = true
  launch_type                        = "FARGATE"
  scheduling_strategy                = "REPLICA"
  depends_on      = [aws_lb_listener.alb_listener]
  load_balancer {
    container_name   = "replace-word-app"
    container_port   = 5000
    target_group_arn = aws_lb_target_group.ecs_rest_api_tg.arn
  }
  network_configuration {
    security_groups  = [aws_security_group.ecs_sg.id]
    subnets          = [aws_subnet.public_1.id, aws_subnet.public_2.id]
  }
}

# # Create an EC2 instance profile.
# resource "aws_iam_instance_profile" "ec2_instance_profile" {
#   name = "ec2_instance_profile"
#   role = aws_iam_role.ec2_role.name
# }

# # Create an EC2 Launch Configuration for the ECS cluster.
# resource "aws_launch_configuration" "ecs_launch_config" {
#   image_id             = data.aws_ami.latest_ecs_ami.image_id
#   security_groups      = [aws_security_group.ecs_sg.id]
#   instance_type        = var.instance_type
#   iam_instance_profile = aws_iam_instance_profile.ec2_instance_profile.name
#   user_data            = "#!/bin/bash\necho ECS_CLUSTER=ecs_cluster >> /etc/ecs/ecs.config"
# }

resource "aws_iam_role" "ecsInstanceRole" {
    name = "ecsInstanceRole"
    assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF
}

resource "aws_iam_role_policy_attachment" "ecsInstanceRole" {
    role = "${aws_iam_role.ecsInstanceRole.name}"
    policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role"
}