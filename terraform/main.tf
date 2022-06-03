provider "docker" {
}

provider "aws" {
  region = "us-east-2"
  default_tags {
    tags = {
      Environment = "dev"
      Terraform   = true
    }
  }
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
    usermod -a -G docker admin
    cd /home/admin
    runuser -u admin -- git clone git@github.com:mesoterra/quest.git
    runuser -u admin -- docker build -t quest_image -f ./quest/docker/Dockerfile
    runuser -u admin -- docker run -d -p 3000:3000 --name quest_container quest_image
    sleep 30
    SECRET_WORD="$(curl -s "http://$(docker inspect quest_container 2>&1 | grep '"IPAddress":' | awk -F'"' '{print $4}'):3000/" | awk '{print $1}')"
    docker stop quest_container
    docker rm quest_container
    runuser -u admin -- docker run -d -p 3000:3000 -e SECRET_WORD=$SECRET_WORD --name quest_container quest_image
    EOF
  tags = {
    component = "dockerparent"
    reason    = "quest"
  }
}

output "Quest_Main_URL" {
  value = "http://${aws_instance.quest_dockerparent.public_dns}:3000/"
}
output "Quest_Docker_Check" {
  value = "http://${aws_instance.quest_dockerparent.public_dns}:3000/docker"
}
output "Quest_Secret_Word_Check" {
  value = "http://${aws_instance.quest_dockerparent.public_dns}:3000/secret_word"
}
output "Quest_Load_Balancer_Check" {
  value = "http://${aws_instance.quest_dockerparent.public_dns}:3000/loadbalanced"
}
output "Quest_TLS_Check" {
  value = "http://${aws_instance.quest_dockerparent.public_dns}:3000/tls"
}

terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
    }
  }
  # Despite using local it is my preference to use an s3 bucket and a dynamodb table for locking.
  backend "local" {
  }
}
