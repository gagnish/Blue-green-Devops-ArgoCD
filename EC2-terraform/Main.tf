resource "aws_security_group" "Server_sg" {
  name        = "Server-Security-Group"
  description = "Open 22,443,465,80,8080,9000,9100,9090,3000"

  # Define a single ingress rule to allow traffic on all specified ports
  ingress = [
    for port in [22, 80, 443,465,8080,9000,9100,9090,3000] : {
      description      = "TLS from VPC"
      from_port        = port
      to_port          = port
      protocol         = "tcp"
      cidr_blocks      = ["0.0.0.0/0"]
      ipv6_cidr_blocks = []
      prefix_list_ids  = []
      security_groups  = []
      self             = false
    }
  ]

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "Server-sg"
  }
}

# DATA For AMI
data "aws_ami" "ubuntu" {
  most_recent = true

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  owners = ["099720109477"] # Canonical
}

# Create the IAM Role and Attach the Administrator Policy
resource "aws_iam_role" "blue_green_role" {
  name = "blue_green-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "blue_green_role_attach" {
  role       = aws_iam_role.blue_green_role.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

# Create an Instance Profile and Attach the Role
resource "aws_iam_instance_profile" "blue_green_instance_profile" {
  name = "blue_green-instance-profile"
  role = aws_iam_role.blue_green_role.name
}


# JENKINS SONARQUBE EC2 INSTANCE
resource "aws_instance" "web" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = "t2.large"
  key_name               = "localppk"
  vpc_security_group_ids = [aws_security_group.Server_sg.id]
  user_data              = templatefile("./EC2.sh", {})

  iam_instance_profile = aws_iam_instance_profile.blue_green_instance_profile.name

  tags = {
    Name = "Server"
  }
  root_block_device {
    volume_size = 30
  }
}
