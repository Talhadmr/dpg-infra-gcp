module "vpc" {
  source = "./modules/vpc"

  project_name   = var.vpc_config.name
  region         = var.region
  subnet_cidr    = var.vpc_config.subnet_cidr
  enable_nat     = var.vpc_config.enable_nat
  enable_iap_ssh = var.vpc_config.enable_iap_ssh
}

module "vm" {
  source = "./modules/vm"

  subnetwork = module.vpc.subnetwork_self_link
  zone       = var.zone

  tags   = var.common_tags
  labels = var.common_labels

  cluster_nodes = var.cluster_nodes

  standalone_vms      = var.standalone_vms
  standalone_defaults = var.standalone_defaults

  depends_on = [module.vpc]
}
