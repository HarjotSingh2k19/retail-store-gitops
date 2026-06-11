variable "aws_region" {
  description = "AWS region to deploy resources"
  type        = string
  default     = "ap-south-1"
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t3.large"
}

variable "key_name" {
  description = "Name of the AWS key pair for SSH access"
  type        = string
}

variable "project_name" {
  description = "Project name used to tag all resources"
  type        = string
  default     = "gitops-factory"
}

variable "my_ip" {
  description = "Your local machine IP for SSH access (format: x.x.x.x/32)"
  type        = string
}