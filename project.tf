resource "aws_vpc" "vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true

  tags = {
    Name      = "example-vpc"
    ManagedBy = "terraform"
  }
}

# Public subnets which has a direct route to the internet. Our ALB
# requires at least 2 public subnets.
resource "aws_subnet" "pub_subnet_1" {
  vpc_id                  = aws_vpc.vpc.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = format("%sa", var.aws_provider_region)
  map_public_ip_on_launch = true

  tags = {
    Name      = "example-pub-subnet-1"
    ManagedBy = "terraform"
  }
}

resource "aws_subnet" "pub_subnet_2" {
  vpc_id                  = aws_vpc.vpc.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = format("%sb", var.aws_provider_region)
  map_public_ip_on_launch = true

  tags = {
    Name      = "example-pub-subnet-2"
    ManagedBy = "terraform"
  }
}

# Private subnet is where our application will be hosted and doesn't
# have a route to the internet.
resource "aws_subnet" "pvt_subnet_1" {
  vpc_id                  = aws_vpc.vpc.id
  cidr_block              = "10.0.3.0/24"
  availability_zone       = format("%sa", var.aws_provider_region)

  tags = {
    Name      = "example-prv-subnet-1"
    ManagedBy = "terraform"
  }
}

resource "aws_internet_gateway" "internet_gateway" {
  vpc_id = aws_vpc.vpc.id

  tags = {
    Name      = "example-igw"
    ManagedBy = "terraform"
  }
}

resource "aws_route_table" "rt" {
  vpc_id = aws_vpc.vpc.id

  tags = {
    Name      = "example-route-table"
    ManagedBy = "terraform"
  }
}

resource "aws_route" "route_to_gateway" {
  route_table_id         = aws_route_table.rt.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.internet_gateway.id
  depends_on             = [aws_route_table.rt]
}

resource "aws_route_table_association" "pub_subnet_1" {
  subnet_id      = aws_subnet.pub_subnet_1.id
  route_table_id = aws_route_table.rt.id
}

resource "aws_route_table_association" "pub_subnet_2" {
  subnet_id      = aws_subnet.pub_subnet_2.id
  route_table_id = aws_route_table.rt.id
}

resource "aws_security_group" "alb_sg" {
  name        = "ALB Security Group"
  description = "Allow incoming traffic from the internet"
  vpc_id      = aws_vpc.vpc.id

  # Allow incoming HTTP traffic from the internet
  ingress {
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
}

data "aws_ami" "amazon_linux_2" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "example-amz-linux-ami"
    values = ["amzn2-ami-hvm*"]
  }
}

resource "aws_lb" "load-balancer" {
  name               = "load-balancer"
  internal           = false
  load_balancer_type = "application"
  subnets            = [aws_subnet.pub_subnet_1.id,aws_subnet.pub_subnet_2.id]
  security_groups    = [aws_security_group.alb_sg.id]
  tags = {
    Name = "example-load-balancer"
  }
}

resource "aws_lb_target_group" "target-group" {
  name     = "target-group"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.vpc.id
}

# By default I set this up as a fixed response until I've provisioned an
# an instance for processing requests.
resource "aws_lb_listener" "front_end_instance" {
  load_balancer_arn = aws_lb.load-balancer.arn
  port              = "80"
  protocol          = "HTTP"
  default_action {
    type = "fixed-response"
    fixed_response {
      content_type = "text/plain"
      message_body = "Fixed response content"
      status_code  = "200"
    }
  }
}

# Web server security group only allows requests from ALB security group. Note,
# this security group is not currently used. I keep it here as a template for when
# I have a instance configured. The main point is to ensure we restrict access to
# the security group of the load balancer.
resource "aws_security_group" "web_sg" {
  name        = "Web Server Security Group"
  description = "Allow incoming traffic from ALB security group"
  vpc_id      = aws_vpc.vpc.id

  # Allow incoming HTTP traffic from ALB in our VPC
  ingress {
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.alb_sg.id]
  }

  # Allow all outbound traffic
  egress {
    from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}