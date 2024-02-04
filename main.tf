terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
    }
  }

  required_version = ">= 1.2.0"
}

provider "aws" {
  region = "us-east-1"
}

data "aws_availability_zones" "available" {}

locals {
  name   = "dev-elephant-walk"
  region = "us-east-1"

  vpc_cidr = "10.0.0.0/16"
  azs      = slice(data.aws_availability_zones.available.names, 0, 3)

  tags = {
    Example = local.name
  }
}

module "vpc" {
  source = "terraform-aws-modules/vpc/aws"
  name   = local.name
  cidr   = local.vpc_cidr

  azs             = local.azs
  private_subnets = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 8, k)]
  public_subnets  = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 8, k + 4)]

  private_subnet_names = ["Private Subnet 1", "Private Subnet 2", "Private Subnet 3"]
  public_subnet_names = ["Public Subnet 1", "Putblic Subnet 2", "Public Subnet 3"]

  enable_dns_hostnames = true
  enable_dns_support   = true

  enable_nat_gateway = true
  single_nat_gateway = true
}

resource "aws_vpc_endpoint" "s3_gateway" {
  vpc_id            = module.vpc.vpc_id
  service_name      = "com.amazonaws.${local.region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = module.vpc.private_route_table_ids
}

data "aws_subnet" "private1" {
  filter {
    name   = "tag:Name"
    values = ["Private Subnet 1"]
  }

  depends_on = [
    module.vpc
  ]
}

data "aws_subnet" "public1" {
  filter {
    name = "tag:Name"
    values = ["Public Subnet 1"]
  }

  depends_on =  [
    module.vpc 
  ]
}

resource "aws_security_group" "cloud_connect" {
  name        = "cloud_connect"
  description = "Security Group for connecting prem to cloud"
  vpc_id      = module.vpc.vpc_id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = -1
    cidr_blocks = ["0.0.0.0/0"]
  }
}
  
  resource "aws_iam_role" "ssm_role" {
    name = "ssm_role"

    assume_role_policy = jsonencode({
      Version = "2012-10-17",
      Statement = [
        {
          Action = "sts:AssumeRole",
          Effect = "Allow",
          Principal = {
            Service = "ec2.amazonaws.com"
          }
        }
      ]
    })
  }

  resource "aws_iam_role_policy_attachment" "ssm_policy" {
    policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
    role       = aws_iam_role.ssm_role.name
  }
  
  resource "aws_iam_instance_profile" "ssm_instance_profile" {
    name = "ssm_instance_profile"
    role = aws_iam_role.ssm_role.name
  }


resource "aws_instance" "app_server" {
  ami           = "ami-0e0a633d6a18a0e00"
  instance_type = "g4dn.xlarge"
  iam_instance_profile = aws_iam_instance_profile.ssm_instance_profile.name
  subnet_id     = data.aws_subnet.private1.id
  # associate_public_ip_address = true
  key_name = "roke-key"
  user_data = templatefile("${path.module}/init_script.tpl", {})
  vpc_security_group_ids = [aws_security_group.cloud_connect.id]

  root_block_device {
    volume_size = 100
    volume_type = "gp3"
  }

  tags = {
    Name = "CaptainsWalk"
  }
}
