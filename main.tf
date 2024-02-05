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

variable "environment" {
  description = "The environment to deploy to"
  type        = string
  default     = "dev"
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

resource "aws_network_interface" "dev-model-network-interface" { 
  subnet_id = data.aws_subnet.private1.id
  security_groups = [aws_security_group.cloud_connect.id]
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

resource "aws_ebs_volume" "Caves_of_Steel" {
  availability_zone = data.aws_availability_zones.available.names[0]
  size              = 190
  type              = "gp3"
  encrypted         = true

  lifecycle {
    prevent_destroy = true
  }

  tags = {
    Name = "Caves of Steel"
  }
}

resource "aws_volume_attachment" "dev-work" {
  device_name = "/dev/sdf"
  volume_id   = aws_ebs_volume.Caves_of_Steel.id
  instance_id = var.environment == "prod" ? aws_instance.dev-model-instance[0].id : data.aws_instances.dev-model-spot-instances.id  
}

resource "aws_launch_template" "dev-model-template" {
  name = "dev-model-template"
  image_id = "ami-0e0a633d6a18a0e00"
  instance_type = "g4dn.xlarge"
  key_name = "roke-key"
  user_data = base64encode(templatefile("${path.module}/init_script.tpl", {}))
  iam_instance_profile {
    name = aws_iam_instance_profile.ssm_instance_profile.name
  }
  network_interfaces {
    device_index = 0
    network_interface_id = aws_network_interface.dev-model-network-interface.id    
  } 

    tags = {
    Name = "CaptainsWalk"
  }
}

resource "aws_instance" "dev-model-instance" {
  ami = "ami-0e0a633d6a18a0e00"
  count = var.environment == "prod" ? 1:0

  launch_template {
    id = aws_launch_template.dev-model-template.id
    version = "$Latest"
  }
}

resource "aws_spot_fleet_request" "dev-model-spot" {
  iam_fleet_role = "arn:aws:iam::550834880252:role/aws-ec2-spot-fleet-tagging-role"
  spot_price = "0.24"
  target_capacity =  var.environment == "dev" ? 1:0
  count = var.environment == "dev" ? 1:0

   launch_template_config {
      launch_template_specification {
        id = aws_launch_template.dev-model-template.id
        version = "$Latest"
      }
   }

  tags = {
    Name = "dev-model-spot"
  }
}

  data "aws_instances" "dev-model-spot-instances" {
    instance_tags = {
          spots = "dev-model-spot" 
    }  
  }
      
