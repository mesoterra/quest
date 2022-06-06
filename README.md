# A Quest
This repo builds out a dockerized Node.js web application on an EC2 instance and places it behind a load balancer with HTTPS enforced.

## Table of Contents
  - [Notes](README.md#notes)
  - [Requirements](README.md#requirements)
  - [Deploy Application](README.md#deploy-application)
  - [Destroy Application](README.md#destroy-application)

## Notes
The architecture deployed consists of a single Docker container running on a single EC2 instance behind an AWS ALB. SSL encryption is a self signed SSL between the internet and the ALB. Traffic to port 80 on the ALB is redirected to HTTPS on port 443. The ALB terminates the HTTPS connection and forwards the traffic from port 443 over HTTP to port 3000 to EC2 instance via an LB target group.

**SSL Encryption:**
The current SSL setup addresses a lot of security risks, however if I were building an enterprise service I would prefer to have additional security measures between the ALB and the containers. Even a self signed SSL with an in-house CA cert installed on each container would be better than nothing. My reasoning for wanting additional security within the application is to mitigate damage from internal compromise as part of the initial design process.

Additionally, the current SSL generation method is intended to simulate using AWS Certificate Manager to create and supply the certificate that is used.

**Docker:**
The docker implementation is not elegant, it works well for the exercise but would not work for the majority of enterprise applications. If I were to design this system with the only requirement being that the node.js application be deployed in a Docker container I would prefer to use something like AWS App Runner. AWS App Runner (AWS AR) provides serverless container hosting with Git integration and provides load balancing and SSL services. Additionally, at a glance, the pricing of AWS AR looks like it might be cheaper than a custom EC2 solution but this requires verification.

Lastly, because Terraform typically will finish before Docker finishes initializing. Since Terraform outputs the URLs needed to verify if the application is running it is possible for the user to see errors if they try to access the URLs too quickly. With this in mind I added a delay into Terraform to give some time for Docker to finish initializing. The delay counter is 120 seconds long and starts immediately after the EC2 instance is finished being created and runs along side the rest of the tasks in Terraform. There are better ways of doing this, but it works for the purposes of this exercise.

**Security Groups:**
I am making use of pre-existing general security groups. In an enterprise environment I would prefer to either have the groups be created by the application or have pre-existing application specific security groups.

**Secret Word:**
I did try to automate the discovery of the `SECRET_WORD` variable, however due to timeliness and life events I decided to handle that manually. Is it possible, yes, I have done very similar things by leveraging headless Firefox via Selenium and Python. I am sure there are also more elegant solutions than I have used in the past.

**ALB:**
I have the ALB access logs pointed to the S3 bucket that Terraform is using for locks. This is not ideal, though it does work. Normally I would have a logging solution, such as Splunk, configured via a different Terraform plan. The Splunk Terraform would setup an S3 bucket for collecting logs within a target VPC and thus ALB would normally use that for the access logs.

## Requirements
This repo requires Terraform 1.2+ as it comes with a new lifecycle feature that was used to trigger a conditional rebuild of a resource.
```
replace_triggered_by
```

https://www.terraform.io/downloads

## Deploy Application
Download this repository.
```
git clone https://github.com/mesoterra/quest.git
```

Grab access keys for an AWS IAM that has access to S3, EC2, and DynamoDB. The below will set the environment variables in most Linux/Unix terminals.
```
export AWS_ACCESS_KEY_ID=KEY_ID_HERE
export AWS_SECRET_ACCESS_KEY=ACCESS_KEY_HERE
```

Move to `quest/terraform/s3_lock`, initialize and apply in order to create our Terraform backend.
```
terraform init
terraform apply
```

Move to the `quest/terraform` directory and initialize it.
```
terraform init
```

Now the first time we apply `quest/terraform/main.tf` it will have a default value for `SECRET_WORD`. We will address this shortly.
```
terraform apply
```

Now in the output of the terraform we are given the URL of the application, specifically we want to use the URL from the `A_Quest_Main_URL` output. On the page look for the key phrase `the secret word is`, the required `SECRET_WORD` value precedes that phrase.

Now we re-apply Terraform with the new `SECRET_WORD` value.
Note: While the below is running you will see `time_sleep.wait_time` which will count down to 120 seconds. This is intended to give the application time to finish its deployment and allow the user to be able to click on the output URLs as soon as Terraform completes.
```
terraform apply --var="SECRET_WORD=VALUE_HERE"
```

Once that is done you can use the URLs in the Terraform output to quickly navigate to the available pages.

## Destroy Application
To destroy the application first go to `quest/terraform` and run the following.
```
terraform destroy --var="SECRET_WORD=VALUE_HERE"
```

Now move to `quest/terraform/s3_lock` and run the below.
```
terraform destroy
```
