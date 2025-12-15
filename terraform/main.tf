module "vpc" {
    source = "./modules/vpc"
}

module "vm" {
    source = "./modules/vm"

    subnetwork = module.vpc.subnetwork_self_link
}
