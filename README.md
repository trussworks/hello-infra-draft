# Hello, World Tutorial

## 1. A Simple Network

The network is one of the first things you'll create when setting up the infrastructure for a new application. The network is where data moves between the internet and the app and the app and any services it needs (e.g., an internal database). The network is one of the primary ways to control access to hosts and services. For example, while the world should be able to reach our application, only the application should be able to directly talk to the database.

We'll start with a simplified [VPC (virtual private cloud)](https://docs.aws.amazon.com/vpc/latest/userguide/what-is-amazon-vpc.html) architecture: one AZ, two subnets (private + public), and a NAT gateway. We'll explain what these are below.

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

Let's go through these.

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

We break apart our network into two pieces: a public subnet where hosts can be reached directly from the internet and a private subnet which only allows internal communication. We use `/24` subnets for simplicity: 10.10.10.x and 10.10.20.y are the available addresses. In a production environment, we'd likely use larger subnets to give more room to grow.

### The gateway

```terraform
  enable_nat_gateway = true
```

Finally, we setup a [NAT gateway](https://docs.aws.amazon.com/vpc/latest/userguide/vpc-nat-gateway.html). This allows the hosts in our private subnets to reach the internet (e.g., to download packages or reach external services) without exposing them to incoming connections. It's the same as your home LAN where you have a private network all your devices are on, they can reach the internet, but they are not directly exposed to incoming connections.
