# ---------- main.tf ----------
terraform {
  required_version = ">= 1.0.0"
  required_providers {
    aws = { source = "hashicorp/aws", version = ">= 4.0" }
    random = { source = "hashicorp/random", version = ">= 3.0" }
  }
}

provider "aws" {
  region = var.aws_region
}

data "aws_caller_identity" "current" {}
data "aws_ami" "amazon_linux_2" {
  most_recent = true
  owners      = ["amazon"]
  filter { name = "name", values = ["amzn2-ami-hvm-*-x86_64-gp2"] }
}
data "aws_availability_zones" "available" { state = "available" }

resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = { Name = "tf-main-vpc" }
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  map_public_ip_on_launch = true
  availability_zone       = data.aws_availability_zones.available.names[0]
  tags = { Name = "tf-public-subnet" }
}

resource "aws_subnet" "private" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = data.aws_availability_zones.available.names[0]
  tags = { Name = "tf-private-subnet" }
}

resource "aws_internet_gateway" "igw" { vpc_id = aws_vpc.main.id; tags = { Name = "tf-igw" } }

resource "aws_route_table" "public" { vpc_id = aws_vpc.main.id; tags = { Name = "tf-public-rt" } }

resource "aws_route" "default_route" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.igw.id
}

resource "aws_route_table_association" "public_assoc" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

resource "aws_security_group" "web_sg" {
  name        = "tf-web-sg"
  description = "Allow SSH and HTTP"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

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

  tags = { Name = "tf-web-sg" }
}

resource "aws_key_pair" "deployer" {
  key_name   = "tf-deployer-key"
  public_key = file(var.public_key_path)
}

resource "aws_instance" "web" {
  ami                         = data.aws_ami.amazon_linux_2.id
  instance_type               = var.instance_type
  subnet_id                   = aws_subnet.public.id
  vpc_security_group_ids      = [aws_security_group.web_sg.id]
  key_name                    = aws_key_pair.deployer.key_name
  associate_public_ip_address = true

  user_data = <<-USERDATA
              #!/bin/bash
              yum update -y
              yum install -y httpd
              systemctl enable httpd
              systemctl start httpd
              echo "Hello from Terraform-deployed EC2" > /var/www/html/index.html
              USERDATA

  tags = { Name = "tf-web-instance" }
}

resource "aws_kms_key" "s3_kms" {
  description             = "KMS key for S3 encryption"
  deletion_window_in_days = 30
  enable_key_rotation     = true

  policy = <<POLICY
{
  "Version": "2012-10-17",
  "Id": "key-default-1",
  "Statement": [
    { "Sid": "Allow administration", "Effect": "Allow",
      "Principal": { "AWS": "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root" },
      "Action": [ "kms:*" ], "Resource": "*" },
    { "Sid": "Allow use for S3", "Effect": "Allow",
      "Principal": { "AWS": "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root" },
      "Action": [ "kms:Encrypt","kms:Decrypt","kms:ReEncrypt*","kms:GenerateDataKey*","kms:DescribeKey" ],
      "Resource": "*" }
  ]
}
POLICY

  tags = { Name = "S3-KMS" }
}

resource "aws_kms_alias" "s3_kms_alias" {
  name          = "alias/S3-KMS"
  target_key_id = aws_kms_key.s3_kms.key_id
}

resource "random_id" "bucket_suffix" { byte_length = 4 }
locals { s3_bucket_name = "exam-logs-${random_id.bucket_suffix.hex}" }

resource "aws_s3_bucket" "logs" {
  bucket = local.s3_bucket_name
  acl    = "private"
  force_destroy = false

  server_side_encryption_configuration {
    rule {
      apply_server_side_encryption_by_default {
        kms_master_key_id = aws_kms_key.s3_kms.arn
        sse_algorithm     = "aws:kms"
      }
    }
  }

  tags = { Name = "exam-logs" }
}

resource "aws_dynamodb_table" "sessions" {
  name         = "sessions"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "SessionId"
  attribute { name = "SessionId", type = "S" }
  tags      = { Name = "sessions-table" }
}
