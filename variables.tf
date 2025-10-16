variable "aws_region" { description = "AWS region to deploy into"; type = string; default = "us-east-1" }
variable "instance_type" { description = "EC2 instance type"; type = string; default = "t3.micro" }
variable "public_key_path" { description = "Path to your SSH public key"; type = string; default = "~/.ssh/id_rsa.pub" }
