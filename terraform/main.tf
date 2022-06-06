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

data "aws_vpcs" "the_only_one" {
  tags = {
    the_only_one = true
  }
}

data "aws_vpc" "the_only_one" {
  count = length(data.aws_vpcs.the_only_one.ids)
  id    = tolist(data.aws_vpcs.the_only_one.ids)[count.index]
}

locals {
  # Setting local because I only have one VPC, this keeps code simple while showing that it is possible to dynamically lookup VPC based on tags.
  vpc_id = data.aws_vpc.the_only_one[0].id
}

# SG are already setup on my personal account so they are being modified and re-used. In an enterprise environment it may be better to have the terraform play create new SG that are application specific.
resource "aws_network_interface" "quest_dockerparent" {
  subnet_id = "subnet-00ed9737a09813375"
  security_groups = ["sg-0b3aa22179f4d5a71"]
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
  # Setup Docker, build and image from this repo via /quest/docker/Dockerfile, then deploy the container while exposing port 3000.
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

resource "aws_lb" "quest" {
  name = "questalb"
  internal = false
  load_balancer_type = "application"
  security_groups = ["sg-0d436c7ea5655efb5"]
  subnets = ["subnet-00ed9737a09813375", "subnet-0c565082bcc43faa3"]
  # in my opinion deletion protection should usually be set to true, however for this case we are setting it to false for conveninece.
  enable_deletion_protection = false
  # typically I would not use the same S3 bucket for storing logs and terraform locks. Normally I would use a logging solution, like Splunk, which would be handled by separate Terraform plans.
  access_logs {
    bucket = "lockbucket-1654296653"
    prefix = "quest-logs"
    enabled = false
  }
}

# Target group to send traffic from ALB to instances via HTTP over port 3000. Acceptable health check responses are 200 or 302.
resource "aws_lb_target_group" "quest" {
  name     = "quest-lb-tg"
  port     = 3000
  protocol = "HTTP"
  vpc_id   = local.vpc_id
  health_check {
    path = "/"
    port = 3000
    healthy_threshold = 6
    unhealthy_threshold = 2
    timeout = 10
    interval = 15
    matcher = "200,302"
  }
}

# Connect instances to lb target group via port 3000.
resource "aws_lb_target_group_attachment" "quest" {
  target_group_arn = aws_lb_target_group.quest.arn
  target_id        = aws_instance.quest_dockerparent.id
  port             = 3000
}

# Listen on port 443 for https traffic and foward it to the lb target group.
resource "aws_lb_listener" "quest_https" {
  load_balancer_arn = aws_lb.quest.arn
  port              = "443"
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-2016-08"
  certificate_arn   = aws_acm_certificate.quest.arn
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.quest.arn
  }
}

# Listen on port 80 for http traffic and redirect it to port 443.
resource "aws_lb_listener" "quest_http_to_https" {
  load_balancer_arn = aws_lb.quest.arn
  port              = "80"
  protocol          = "HTTP"
  default_action {
    type = "redirect"
    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}

# Creating an SSL certificate in this manner is not desirable, the method used is meant to simulate the use of AWS Certificate Manager.
# Generate SSL key.
resource "tls_private_key" "quest" {
  algorithm = "RSA"
  rsa_bits = 4096
}

# Generate a self signed ssl that will only be good for 7200 hours. The domain used is the ALB DNS name.
resource "tls_self_signed_cert" "quest" {
  private_key_pem = tls_private_key.quest.private_key_pem
  subject {
    common_name = aws_lb.quest.dns_name
    organization = "Quest"
  }
  validity_period_hours = 7200
  allowed_uses = [
    "key_encipherment",
    "server_auth",
  ]
}

# Import the self signed SSL for use with the ALB.
resource "aws_acm_certificate" "quest" {
  private_key      = tls_private_key.quest.private_key_pem
  certificate_body = tls_self_signed_cert.quest.cert_pem
  # this lifecycle argument is required in order for the ALB to be removed before this SSL is removed during terraform destroy.
  lifecycle {
    create_before_destroy = true
  }
}

# This resource will rebuilt when var.SECRET_WORD changes value. This is used to cause the EC2 instance that contains our Docker container to rebuild.
resource "null_resource" "secret_word_update" {
  triggers = {
    SECRET_WORD = var.SECRET_WORD
  }
}
# This delay starts immediately after the EC2 instance finishes creation and runs along side the other tasks in Terraform. It is intended to give the application time to finish initializing so the end user isn't as likely to be exposed to errors. This can be done better but it works for now.
resource "time_sleep" "wait_time" {
  depends_on = [aws_instance.quest_dockerparent]
  create_duration = "120s"
  triggers = {
    SECRET_WORD = var.SECRET_WORD
  }
}

resource "null_resource" "sleeping" {
  depends_on = [time_sleep.wait_time]
  triggers = {
    SECRET_WORD = var.SECRET_WORD
  }
}

output "A_Quest_Main_URL" {
  value = "http://${aws_lb.quest.dns_name}/"
}
output "B_Quest_Docker_Check" {
  value = "http://${aws_lb.quest.dns_name}/docker"
}
output "C_Quest_Secret_Word_Check" {
  value = "http://${aws_lb.quest.dns_name}/secret_word"
}
output "D_Quest_Load_Balancer_Check" {
  value = "http://${aws_lb.quest.dns_name}/loadbalanced"
}
output "E_Quest_TLS_Check" {
  value = "http://${aws_lb.quest.dns_name}/tls"
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
