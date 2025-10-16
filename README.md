# Terraform AWS Infrastructure

Deploys:
- VPC with public/private subnets
- EC2 instance in public subnet
- Security Group (SSH & HTTP)
- KMS key for S3 encryption
- S3 bucket with server-side encryption
- DynamoDB table for session storage

Usage:
terraform init
terraform plan
terraform apply
