provider "aws" {
  region = local.region
}

locals {
  name            = "launch_template-${random_string.suffix.result}"
  cluster_version = "1.20"
  region          = "eu-west-1"
}

################################################################################
# EKS Module
################################################################################

module "eks" {
  source                          = "../.."
  cluster_name                    = local.name
  cluster_version                 = local.cluster_version
  subnets                         = module.vpc.private_subnets
  vpc_id                          = module.vpc.vpc_id 

  worker_groups_launch_template = [
    {
      name                          = "windows"
      platform                      = "windows"
      instance_type                 = "t3.small" 
      asg_desired_capacity          = 2 
      root_volume_size              = 300 
      additional_ebs_volumes = [{
        block_device_name = "/dev/sda1",
        volume_size       = 300
      }]

      tags = [
        {
          key                 = "OS"
          value               = "windows"
          propagate_at_launch = true
        },
        {
          key                 = "k8s.io/cluster-autoscaler/${local.name}"
          value               = "owned"
          propagate_at_launch = true
        },
        {
          key                 = "k8s.io/cluster-autoscaler/enabled"
          value               = true
          propagate_at_launch = true
        }
      ]
    },
    // default Linux worker group launch template for big workloads
  ]
}

################################################################################
# Kubernetes provider configuration
################################################################################

data "aws_eks_cluster" "cluster" {
  name = module.eks.cluster_id
}

data "aws_eks_cluster_auth" "cluster" {
  name = module.eks.cluster_id
}

provider "kubernetes" {
  host                   = data.aws_eks_cluster.cluster.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.cluster.certificate_authority[0].data)
  token                  = data.aws_eks_cluster_auth.cluster.token
}

################################################################################
# Supporting Resources
################################################################################

data "aws_availability_zones" "available" {
}

resource "random_string" "suffix" {
  length  = 8
  special = false
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 3.0"

  name                 = local.name
  cidr                 = "10.0.0.0/16"
  azs                  = data.aws_availability_zones.available.names
  private_subnets      = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  public_subnets       = ["10.0.4.0/24", "10.0.5.0/24", "10.0.6.0/24"]
  enable_nat_gateway   = true
  single_nat_gateway   = true
  enable_dns_hostnames = true

  public_subnet_tags = {
    "kubernetes.io/cluster/${local.name}" = "shared"
    "kubernetes.io/role/elb"              = "1"
  }

  private_subnet_tags = {
    "kubernetes.io/cluster/${local.name}" = "shared"
    "kubernetes.io/role/internal-elb"     = "1"
  }

  tags = {
    Example    = local.name
    GithubRepo = "terraform-aws-eks"
    GithubOrg  = "terraform-aws-modules"
  }
}
