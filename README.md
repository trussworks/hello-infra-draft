# Hello, World

This is a work in progress.

## WIP Notes

This section is internal notes. Tutorial begins in the next section: [#Network](#network).

Experimenting with the idea of a simple, Hello, World flavored stack that someone could standup and have a base understanding of in a single day.

Topics to cover in the simple stack:

* Frontmatter
  * terraform.tf: AWS provider
* VPC: `terraform-aws-modules/vpc/aws`
* ACM: `trussworks/acm-cert/aws`
* ALB: `trussworks/alb-web-containers/aws`
* DNS: route53 resource records
* ECS: `trussworks/ecs-service/aws`

Dependency relation: (DNS, ECS) -> ALB -> (VPC, ACM)

Directions we can head to extend things:

* Remove hardcoded values (like names) and parameterize them into locals/variables.
* Enable ALB access logs.
* Pull something out of ParamterStore or DynamoDB.
* Add a database.

Directions we can head to dissect things:

* Go through all the resources created by each module
* Build simplified versions of the modules from scratch
* Dive into various topics we glossed over

## Network

The network is one of the first things you'll create when setting up the infrastructure for a new application. The network is where data moves between the internet and the app and the app and any services it needs (e.g., an internal database). The network is one of the primary ways to control access to hosts and services. For example, while the world should be able to reach our application, only the application should be able to directly talk to the database.

We'll start with a simplified VPC[^vpc] (virtual private cloud) architecture: one AZ, two subnets (private + public), and a NAT gateway. We'll explain what these are below.

Here's the Terraform code for creating our simple network:

```terraform
module "vpc" {
  source = "terraform-aws-modules/vpc/aws"

  name = "hello"
  cidr = "10.10.0.0/16"

  azs             = ["us-west-2a"]
  private_subnets = ["10.10.10.0/24"]
  public_subnets  = ["10.10.20.0/24"]

  enable_nat_gateway = true
}
```

Let's go through it.

### The module

```terraform
module "vpc" {
  source = "terraform-aws-modules/vpc/aws"
```

We use the [official VPC module](https://registry.terraform.io/modules/terraform-aws-modules/vpc/aws/latest) to create the various resources one needs when setting up a network. Behind the scenes, this simple configuration is going to result in 12 new resources being created! It's a great module that keeps simple things simple but provides the flexibility to configure more complex architectures. Use it.

### The name

```terraform
  name = "hello"
```

Our VPC needs a name and it needs to be unique to the region. We'll use the "hello" monicker throughout the code to keep things simple and consistent. We'll talk about more robust naming strategies later.

### The CIDR

```terraform
  cidr = "10.10.0.0/16"
```

Everything will live within this address space. We use a `/16` since this is a common size and easy to understand: all our IPs will be of the form 10.10.x.y. Understanding CIDR, subnets, masks, etc. can be complicated and it's way out of scope for this tutorial. Here's a visual tool for seeing how changing the numbers in a CIDR changes the available addresses we can use: [cidr.xyz](https://cidr.xyz/).

### The availability zones

```terraform
  azs             = ["us-west-2a"]
```

Every AWS region has multiple availability zones (AZs):

```sh
$ aws ec2 describe-availability-zones --region us-west-2 | jq -r '.AvailabilityZones[].ZoneName'
us-west-2a
us-west-2b
us-west-2c
us-west-2d
```

Each AZ is it's own self-contained data center. If an AZ fails (e.g., a devastating network change is rolled out or the building catches fire), the other AZs in the region should still be available. It's best practice to use two or more AZs in your production environment to ensure your application is available. For now, we start with a single AZ to keep things simple.

NOTE: The mapping between AZs and physical datacenters is defined by AWS per account. In other words, the physical location of `us-west-2a` in one account may or may not be the same as `us-west-2a` in another account.

### The subnets

```terraform
  private_subnets = ["10.10.10.0/24"]
  public_subnets  = ["10.10.20.0/24"]
```

We divide the network into public and private address spaces. Network subdivision are called a subnets. Hosts that need to be reachable from the internet will get an address from the public subnet and everything else will get an address from the private subnet.

Subnets are tied to AZs. This means every AZ will need its own public and private subnet. Since we're using one AZ, we define two subnets. We use `/24` subnets for simplicity: 10.10.10.x and 10.10.20.y are the available addresses. In a production environment, we'd likely use larger subnets to give more room to grow.

If we were using two AZs, we'd need 4 subnets (2 private, 2 public). Here's an example:

```terraform
  azs             = ["us-west-2a", "us-west-2b"]
  private_subnets = ["10.10.10.0/24", "10.10.11.0/24"]
  public_subnets  = ["10.10.20.0/24", "10.10.21.0/24"]
```

### The gateway

```terraform
  enable_nat_gateway = true
```

Finally, we setup a NAT gateway[^nat]. This allows the hosts in our private subnets to reach the internet (e.g., to download packages or reach external services) without exposing them to incoming connections. It's the same as your home LAN where you have a private network all your devices are on, they can reach the internet, but they are not directly exposed to incoming connections.

## Load Balancer

The load balancer[^alb] receives HTTP requests from the internet, sends them to our application container, and returns the response. In general, this is one of the few pieces of infrastructure that will be on our public subnet and accessible via the internet.

### The certificate

We will not even entertain the notion of serving our application over an unencrypted connection. With services like AWS Certificate Manager (ACM)[^acm] and Let's Encrypt making it easy to both provision and rotate TLS certificates, it's an act of negligence to do otherwise. Our service will be visited at `https://hello.sandbox.truss.coffee`.

Here's the Terraform code for provisioning a TLS cert with AWS ACM

```terraform
# TLS certificate
module "alb_tls_cert" {
  source = "trussworks/acm-cert/aws"

  domain_name = "hello.sandbox.truss.coffee"
  zone_name   = "sandbox.truss.coffee"

  environment = "sandbox"
}
```

Let's go through it.

#### The module

```terraform
module "alb_tls_cert" {
  source = "trussworks/acm-cert/aws"

```

We use [TrussWorks' acm-cert module](https://registry.terraform.io/modules/trussworks/acm-cert/aws/latest) to do the dance needed to get a valid certificate. Behind the scenes it's using Amazon Route 53[^route53] to validate we control the domain we want a certificate for (`hello.sandbox.truss.coffee`) while sheparding ACM through it's  provisioning process.

A lovely feature of ACM is that it will automatically renew our certificate when it's near it's expiration. This avoids a common source of service outage.

#### The domain

```terraform
  domain_name = "hello.sandbox.truss.coffee"
  zone_name   = "sandbox.truss.coffee"
```

The main bit here is `domain_name`. This must match the name folks will use in their browser to visit our site.

The `zone_name` specifies where the DNS records will be written in Route 53. For now, we'll leave this as a black box. This Route 53 zone will already exist and we would have been told to use this when creating subdomain of `sandbox.truss.coffee`.

#### Tagging

```terraform
  environment = "sandbox"
```

Not actually needed for making certificates, the TrussWorks module requires we pass in the "environment" so it can tag the resources being created. We'll talk more about tagging later.

### The load balancer

```terraform
module "alb" {
  source = "trussworks/alb-web-containers/aws"

  name        = "hello"
  environment = "sandbox"

  alb_vpc_id                  = module.vpc.vpc_id
  alb_subnet_ids              = module.vpc.public_subnets
  alb_default_certificate_arn = module.alb_tls_cert.acm_arn

  container_port     = 8080
  container_protocol = "HTTP"

  logs_s3_bucket = ""
}
```

## DNS

```terraform
data "aws_route53_zone" "main" {
  name = "sandbox.truss.coffee"
}

resource "aws_route53_record" "main" {
  name    = "hello"
  zone_id = data.aws_route53_zone.main.zone_id
  type    = "A"

  alias {
    name                   = module.alb.alb_dns_name
    zone_id                = module.alb.alb_zone_id
    evaluate_target_health = false
  }
}
```

## Container

```terraform
resource "aws_ecs_cluster" "main" {
  name = "hello"
}

module "ecs-service" {
  source = "trussworks/ecs-service/aws"

  name        = "hello"
  environment = "sandbox"

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
```

## Footnotes

[^vpc]: [What is Amazon VPC?](https://docs.aws.amazon.com/vpc/latest/userguide/what-is-amazon-vpc.html)
[^nat]: [Amazon VPC: NAT gateways](https://docs.aws.amazon.com/vpc/latest/userguide/vpc-nat-gateway.html)
[^alb]: [What is an Application Load Balancer?](https://docs.aws.amazon.com/elasticloadbalancing/latest/application/introduction.html)
[^acm]: [What Is AWS Certificate Manager?](https://docs.aws.amazon.com/acm/latest/userguide/acm-overview.html)
[^route53]: [What is Amazon Route 53?](https://docs.aws.amazon.com/Route53/latest/DeveloperGuide/Welcome.html)
