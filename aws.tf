provider "aws" {
    shared_credentials_file = "credentials"
    region = "us-east-1"  # Replace with your desired AWS region
}

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.0"
    }
  }
}

resource "aws_iam_role" "flight_api_task_execution_role" {
  name               = "flight_api-task-execution-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_task_assume_role.json
}

data "aws_iam_policy_document" "ecs_task_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

# Normally we'd prefer not to hardcode an ARN in our Terraform, but since this is
# an AWS-managed policy, it's okay.
data "aws_iam_policy" "ecs_task_execution_role" {
  arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# Attach the above policy to the execution role.
resource "aws_iam_role_policy_attachment" "ecs_task_execution_role" {
  role       = aws_iam_role.flight_api_task_execution_role.name
  policy_arn = data.aws_iam_policy.ecs_task_execution_role.arn
}

resource "aws_vpc" "app_vpc" {
  cidr_block = "10.0.0.0/16"
}

resource "aws_subnet" "public_d" {
  vpc_id            = aws_vpc.app_vpc.id
  cidr_block        = "10.0.1.0/25"
  availability_zone = "us-east-1d"

  tags = {
    "Name" = "public | us-east-1d"
  }
}

resource "aws_subnet" "private_d" {
  vpc_id            = aws_vpc.app_vpc.id
  cidr_block        = "10.0.2.0/25"
  availability_zone = "us-east-1d"

  tags = {
    "Name" = "private | us-east-1d"
  }
}

resource "aws_subnet" "public_e" {
  vpc_id            = aws_vpc.app_vpc.id
  cidr_block        = "10.0.1.128/25"
  availability_zone = "us-east-1e"

  tags = {
    "Name" = "public | us-east-1e"
  }
}

resource "aws_subnet" "private_e" {
  vpc_id            = aws_vpc.app_vpc.id
  cidr_block        = "10.0.2.128/25"
  availability_zone = "us-east-1e"

  tags = {
    "Name" = "private | us-east-1e"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.app_vpc.id
  tags = {
    "Name" = "public"
  }
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.app_vpc.id
  tags = {
    "Name" = "private"
  }
}

resource "aws_route_table_association" "public_d_subnet" {
  subnet_id      = aws_subnet.public_d.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "private_d_subnet" {
  subnet_id      = aws_subnet.private_d.id
  route_table_id = aws_route_table.private.id
}

resource "aws_route_table_association" "public_e_subnet" {
  subnet_id      = aws_subnet.public_e.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "private_e_subnet" {
  subnet_id      = aws_subnet.private_e.id
  route_table_id = aws_route_table.private.id
}

resource "aws_eip" "nat" {
  vpc = true
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.app_vpc.id
}

resource "aws_nat_gateway" "ngw" {
  subnet_id     = aws_subnet.public_d.id
  allocation_id = aws_eip.nat.id

  depends_on = [aws_internet_gateway.igw]
}

resource "aws_route" "public_igw" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.igw.id
}

resource "aws_route" "private_ngw" {
  route_table_id         = aws_route_table.private.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.ngw.id
}

resource "aws_security_group" "http" {
  name        = "http"
  description = "HTTP traffic"
  vpc_id      = aws_vpc.app_vpc.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "TCP"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "https" {
  name        = "https"
  description = "HTTPS traffic"
  vpc_id      = aws_vpc.app_vpc.id

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "TCP"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "egress_all" {
  name        = "egress-all"
  description = "Allow all outbound traffic"
  vpc_id      = aws_vpc.app_vpc.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "ingress_api" {
  name        = "ingress-api"
  description = "Allow ingress to API"
  vpc_id      = aws_vpc.app_vpc.id

  ingress {
    from_port   = 5000
    to_port     = 5000
    protocol    = "TCP"
    cidr_blocks = ["0.0.0.0/0"]
  }
}


resource "aws_ecs_task_definition" "flight-api" {
  family = "flight-api"

  container_definitions = <<EOF
  [
    {
      "name": "flight-api",
      "image": "rv0lt/flightradartest:v1",
      "portMappings": [
        {
          "containerPort": 5000
        }
      ]
    }
  ]
  EOF

  execution_role_arn = aws_iam_role.flight_api_task_execution_role.arn
  # These are the minimum values for Fargate containers.
  cpu = 256
  memory = 512
  requires_compatibilities = ["FARGATE"]

  # This is required for Fargate containers (more on this later).
  network_mode = "awsvpc"
}

resource "aws_lb_target_group" "flight_api" {
  name        = "flight-api"
  port        = 5000
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = aws_vpc.app_vpc.id

  health_check {
    enabled = true
    path    = "/health"
  }

  depends_on = [aws_alb.flight_api]
}

resource "aws_alb" "flight_api" {
  name               = "flight-api-lb"
  internal           = false
  load_balancer_type = "application"

  subnets = [
    aws_subnet.public_d.id,
    aws_subnet.public_e.id,
  ]

  security_groups = [
    aws_security_group.http.id,
    aws_security_group.https.id,
    aws_security_group.egress_all.id,
  ]

  depends_on = [aws_internet_gateway.igw]
}

resource "aws_alb_listener" "flight_api_http" {
  load_balancer_arn = aws_alb.api.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.flight_api.arn
  }
}

output "alb_url" {
  value = "http://${aws_alb.api.dns_name}"
}

resource "aws_ecs_cluster" "app" {
   name = "app"
}

resource "aws_ecs_service" "flight_api" {
  name            = "flight_api"
  task_definition = "aws_ecs_task_definition.flight_api.arn"
  cluster         = aws_ecs_cluster.app.id
  launch_type     = "FARGATE"

 network_configuration {
   assign_public_ip = false

   security_groups = [
     aws_security_group.egress_all.id,
     aws_security_group.ingress_api.id,
   ]

   subnets = [
     aws_subnet.private_d.id,
     aws_subnet.private_e.id,
   ]
 }
 load_balancer {
   target_group_arn = aws_lb_target_group.flight_api.arn
   container_name   = "flight_api"
   container_port   = "5000"
 }
desired_count = 1
}


