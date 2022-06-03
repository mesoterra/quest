provider "aws" {
  region = "us-east-2"
  default_tags {
    tags = {
      Environment = "dev"
      Terraform   = true
    }
  }
}

# variables, normally this would be it's own variables.tf but this is a very simple plan
variable "SECRET_WORD" {
  type = string
  description = "The secret word displayed on the '/' page of the application."
  default = "test"
}

# SG are already setup on my personal account so they are being re-used. In an enterprise environment it may be better to have the terraform play create new SG that are application specific.
resource "aws_network_interface" "quest_dockerparent" {
  subnet_id = "subnet-00ed9737a09813375"
  security_groups = ["sg-026d277d7cffc5428"]
}

data "aws_ami" "os_ami" {
  name_regex = "^amzn2-ami-kernel-[5-9].[0-9]{1,2}-*"
  most_recent = true
  owners = ["137112412989"]
  filter {
    name = "architecture"
    values = ["x86_64"]
  }
  filter {
    name = "virtualization-type"
    values = ["hvm"]
  }
  filter {
    name = "root-device-type"
    values = ["ebs"]
  }
}

resource "aws_instance" "quest_dockerparent" {
  ami = data.aws_ami.os_ami.id
  instance_type = "t2.micro"
  key_name = "debug"
  network_interface {
    network_interface_id = aws_network_interface.quest_dockerparent.id
    device_index = 0
  }
  user_data = <<-EOF
    #!/usr/bin/env bash
    sudo su -
    yum update -y
    yum install -y docker git
    systemctl enable docker
    systemctl start docker
    usermod -a -G docker ec2-user
    cd /home/ec2-user
    runuser -u ec2-user -- git clone https://github.com/mesoterra/quest.git
    runuser -u ec2-user -- docker build -t quest_image ./quest/docker
    runuser -u ec2-user -- docker run -d -p 3000:3000 -e SECRET_WORD=${var.SECRET_WORD} --name quest_container quest_image
    EOF
  tags = {
    component = "dockerparent"
    reason    = "quest"
  }
  # This lifecycle block requires terraform 1.2+ for the 'replace_triggered_by' flag.
  lifecycle {
    replace_triggered_by = [
      null_resource.secret_word_update.id
    ]
  }
}

resource "null_resource" "secret_word_update" {
  triggers = {
    SECRET_WORD = var.SECRET_WORD
  }
}

output "A_Quest_Main_URL" {
  value = "http://${aws_instance.quest_dockerparent.public_dns}:3000/"
}
output "B_Quest_Docker_Check" {
  value = "http://${aws_instance.quest_dockerparent.public_dns}:3000/docker"
}
output "C_Quest_Secret_Word_Check" {
  value = "http://${aws_instance.quest_dockerparent.public_dns}:3000/secret_word"
}
output "D_Quest_Load_Balancer_Check" {
  value = "http://${aws_instance.quest_dockerparent.public_dns}:3000/loadbalanced"
}
output "E_Quest_TLS_Check" {
  value = "http://${aws_instance.quest_dockerparent.public_dns}:3000/tls"
}

terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
    }
  }
  # Despite using local it is my preference to use an s3 bucket and a dynamodb table for locking.
  backend "s3" {
    bucket = "lockbucket-1654296653"
    key = "quest/terraform.tfstate"
    region = "us-east-2"
  }
}
