provider "aws" {
  region = "us-west-2"
}

#
# 1. Network
#

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 2.64.0"

  name = "hello-brainsik"
  cidr = "10.0.0.0/16"

  azs             = ["us-west-2a", "us-west-2b"]
  private_subnets = ["10.0.10.0/24", "10.0.11.0/24"]
  public_subnets  = ["10.0.20.0/24", "10.0.21.0/24"]

  enable_nat_gateway = true
  single_nat_gateway = true

  tags = {
    Automation  = "Terraform"
    Environment = "brainsik"
  }
}

#
# 2. Load Balancer
#

# TLS certificate
module "alb_tls_cert" {
  source  = "trussworks/acm-cert/aws"
  version = "~> 3.0.2"

  domain_name = "hello.sandbox.truss.coffee"
  zone_name   = "sandbox.truss.coffee"

  environment = "brainsik"
}

module "alb" {
  source = "/Users/brainsik/src/trussworks/terraform-aws-alb-web-containers"
  # version = "5.1.1"

  name        = "hello"
  environment = "brainsik"

  alb_vpc_id                  = module.vpc.vpc_id
  alb_subnet_ids              = module.vpc.public_subnets
  alb_default_certificate_arn = module.alb_tls_cert.acm_arn

  container_port     = 8080
  container_protocol = "HTTP"

  logs_s3_bucket = ""
}

#
# 3. DNS
#

data "aws_route53_zone" "sandbox" {
  name = "sandbox.truss.coffee"
}

resource "aws_route53_record" "main" {
  name    = "hello"
  zone_id = data.aws_route53_zone.sandbox.zone_id
  type    = "A"

  alias {
    name                   = module.alb.alb_dns_name
    zone_id                = module.alb.alb_zone_id
    evaluate_target_health = false
  }
}

#
# 4. Container
#

resource "aws_ecs_cluster" "main" {
  name = "hello-brainsik"

  tags = {
    Automation  = "Terraform"
    Environment = "brainsik"
  }
}

module "ecs-service" {
  source  = "trussworks/ecs-service/aws"
  version = "5.1.1"

  name        = "hello"
  environment = "brainsik"

  ecs_cluster     = aws_ecs_cluster.main
  ecs_use_fargate = true

  ecs_vpc_id     = module.vpc.vpc_id
  ecs_subnet_ids = module.vpc.private_subnets

  associate_alb      = true
  alb_security_group = module.alb.alb_security_group_id
  lb_target_groups = [
    {
      container_port              = 8080
      container_health_check_port = 8080
      lb_target_group_arn         = module.alb.alb_target_group_id
    }
  ]

  kms_key_id = null
}
