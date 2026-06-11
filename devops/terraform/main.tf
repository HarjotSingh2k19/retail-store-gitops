# EC2 Instance
resource "aws_instance" "main" {
  ami                    = "ami-0f58b397bc5c1f2e8" # Ubuntu 24.04 LTS ap-south-1
  instance_type          = var.instance_type
  key_name               = var.key_name
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.main.id]

  root_block_device {
    volume_size = 30
    volume_type = "gp3"
  }

  user_data = <<-USERDATA
    #!/bin/bash
    apt-get update -y
  USERDATA

  tags = {
    Name    = "${var.project_name}-server"
    Project = var.project_name
  }
}