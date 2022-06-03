provider "aws" {
  region = "us-east-2"
  default_tags {
    tags = {
      Terraform   = true
    }
  }
}

resource "aws_s3_bucket" "lockbucket" {
  bucket = "lockbucket-1654296653"
  force_destroy = true
#  lifecycle {
#    prevent_destroy = true
#  }
}

resource "aws_s3_bucket_versioning" "lockbucket" {
  bucket = aws_s3_bucket.lockbucket.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_dynamodb_table" "lockbucket" {
  name = "lockbucket-1654296653"
  read_capacity = 1
  write_capacity = 1
  hash_key = "LockID"
  attribute {
    name = "LockID"
    type = "S"
  }
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
