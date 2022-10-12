terraform {
  required_version = "1.2.9"
  required_providers {
    aws = {
      source = "hashicorp/aws"
    }
    tls = {
      source = "hashicorp/tls"
    }
    random = {
      source = "hashicorp/random"
    }
    helm = {
      source = "hashicorp/helm"
    }
    rancher2 = {
      source = "rancher/rancher2"
    }
  }
}

provider "aws" {
  region = local.region
}

module "aws_shared" {
  source              = "./aws_shared"
  project_name        = local.project_name
  ssh_public_key_path = local.ssh_public_key_path
}

module "aws_network" {
  source            = "./aws_network"
  region            = local.region
  availability_zone = local.availability_zone
  project_name      = local.project_name
}

module "secret" {
  source = "./secret"
}

module "bastion" {
  depends_on            = [module.aws_network]
  source                = "./aws_host"
  ami                   = local.bastion_ami
  availability_zone     = local.availability_zone
  project_name          = local.project_name
  name                  = "bastion"
  ssh_key_name          = module.aws_shared.key_name
  ssh_private_key_path  = local.ssh_private_key_path
  subnet_id             = module.aws_network.public_subnet_id
  vpc_security_group_id = module.aws_network.public_security_group_id
}

module "upstream_cluster" {
  source                        = "./aws_rke2"
  ami                           = local.upstream_ami
  instance_type                 = local.upstream_instance_type
  availability_zone             = local.availability_zone
  project_name                  = local.project_name
  name                          = "upstream"
  server_count                  = local.upstream_server_count
  agent_count                   = local.upstream_agent_count
  ssh_key_name                  = module.aws_shared.key_name
  ssh_private_key_path          = local.ssh_private_key_path
  ssh_bastion_host              = module.bastion.public_name
  subnet_id                     = module.aws_network.private_subnet_id
  vpc_security_group_id         = module.aws_network.private_security_group_id
  k8s_api_ssh_tunnel_local_port = 6443
  additional_ssh_tunnels        = [[3000, 443]]
  rke2_version                  = local.upstream_rke2_version
  max_pods                      = local.upstream_max_pods
  node_cidr_mask_size           = local.upstream_node_cidr_mask_size
  sans                          = [local.upstream_san]
  secret_values                 = module.secret.values
}

provider "helm" {
  kubernetes {
    host                   = "https://${local.upstream_san}:6443"
    client_certificate     = module.secret.values.master_user_cert
    client_key             = module.secret.values.master_user_key
    cluster_ca_certificate = module.secret.values.server_ca_cert
  }
}

module "rancher" {
  depends_on       = [module.upstream_cluster]
  count            = local.upstream_server_count > 0 ? 1 : 0
  source           = "./rancher"
  public_name      = local.upstream_san
  private_name     = module.upstream_cluster.first_server_private_name
  api_token_string = module.secret.values.api_token_string
  chart            = local.rancher_chart
}

module "downstream_cluster" {
  source                        = "./aws_rke2"
  count                         = 1
  ami                           = local.downstream_ami
  instance_type                 = local.downstream_instance_type
  availability_zone             = local.availability_zone
  project_name                  = local.project_name
  name                          = "downstream-${count.index}"
  server_count                  = local.downstream_server_count
  agent_count                   = local.downstream_agent_count
  ssh_key_name                  = module.aws_shared.key_name
  ssh_private_key_path          = local.ssh_private_key_path
  ssh_bastion_host              = module.bastion.public_name
  subnet_id                     = module.aws_network.private_subnet_id
  vpc_security_group_id         = module.aws_network.private_security_group_id
  k8s_api_ssh_tunnel_local_port = 6444 + count.index
  rke2_version                  = local.downstream_rke2_version
  max_pods                      = local.downstream_max_pods
  node_cidr_mask_size           = local.downstream_node_cidr_mask_size
  sans                          = [local.downstream_san]
  secret_values                 = module.secret.values
}
