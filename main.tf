terraform {
  backend "s3" {
    bucket = "YOUR_BACKEND"
    key    = "YOUR_KEY"
    region = "YOUR_REGION"
  }
}

locals {
  env_name         = "staging"
  aws_region       = "YOUR_REGION"
  k8s_cluster_name = "ms-cluster"
}

variable "mysql_password" {
  type        = string
  description = "Expected to be retrieved from environment variable TF_VAR_mysql_password"
}

module "aws-network" {
  source = "github.com/implementing-microservices/module-aws-network"

  env_name              = local.env_name
  vpc_name              = "msur-VPC"
  cluster_name          = local.k8s_cluster_name
  aws_region            = local.aws_region
  main_vpc_cidr         = "10.10.0.0/16"
  public_subnet_a_cidr  = "10.10.0.0/18"
  public_subnet_b_cidr  = "10.10.64.0/18"
  private_subnet_a_cidr = "10.10.128.0/18"
  private_subnet_b_cidr = "10.10.192.0/18"
}

module "aws-kubernetes-cluster" {
  source = "github.com/implementing-microservices/module-aws-kubernetes"

  ms_namespace       = "microservices"
  env_name           = local.env_name
  aws_region         = local.aws_region
  cluster_name       = local.k8s_cluster_name
  vpc_id             = module.aws-network.vpc_id
  cluster_subnet_ids = module.aws-network.subnet_ids

  nodegroup_subnet_ids     = module.aws-network.private_subnet_ids
  nodegroup_disk_size      = "20"
  nodegroup_instance_types = ["t3.medium"]
  nodegroup_desired_size   = 1
  nodegroup_min_size       = 1
  nodegroup_max_size       = 5
}

module "nginx-ingress" {
  source = "github.com/implementing-microservices/module-aws-nginx-ingress"

  kubernetes_cluster_id        = module.aws-kubernetes-cluster.eks_cluster_id
  kubernetes_cluster_name      = module.aws-kubernetes-cluster.eks_cluster_name
  kubernetes_cluster_cert_data = module.aws-kubernetes-cluster.eks_cluster_certificate_data
  kubernetes_cluster_endpoint  = module.aws-kubernetes-cluster.eks_cluster_endpoint
}

module "argo-cd-server" {
  source = "github.com/implementing-microservices/module-argo-cd"

  kubernetes_cluster_id        = module.aws-kubernetes-cluster.eks_cluster_id
  kubernetes_cluster_name      = module.aws-kubernetes-cluster.eks_cluster_name
  kubernetes_cluster_cert_data = module.aws-kubernetes-cluster.eks_cluster_certificate_data
  kubernetes_cluster_endpoint  = module.aws-kubernetes-cluster.eks_cluster_endpoint

  eks_nodegroup_id = module.aws-kubernetes-cluster.eks_cluster_nodegroup_id
}

module "aws-databases" {
  source = "github.com/implementing-microservices/module-aws-db"

  aws_region     = local.aws_region
  mysql_password = var.mysql_password
  vpc_id         = module.aws-network.vpc_id
  eks_id         = module.aws-kubernetes-cluster.eks_cluster_id
  subnet_a_id    = module.aws-network.private_subnet_ids[0]
  subnet_b_id    = module.aws-network.private_subnet_ids[1]
  env_name       = local.env_name
  route53_id     = module.aws-network.route53_id
}
