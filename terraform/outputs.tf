output "vpc_network_name" {
  description = "The name of the VPC network"
  value       = module.vpc.network_name
}

output "vpc_subnet_name" {
  description = "The name of the subnet"
  value       = module.vpc.subnetwork_name
}

output "vpc_subnet_cidr" {
  description = "The CIDR block of the subnet"
  value       = module.vpc.subnet_cidr
}


output "cluster_nodes" {
  description = "All Kubernetes cluster nodes (for Kubespray inventory)"
  value       = module.vm.cluster_nodes
}

output "master_nodes" {
  description = "Kubernetes master/control-plane nodes"
  value       = module.vm.master_nodes
}

output "worker_nodes" {
  description = "Kubernetes worker nodes"
  value       = module.vm.worker_nodes
}


output "standalone_nodes" {
  description = "Standalone VMs (outside Kubernetes cluster)"
  value       = module.vm.standalone_nodes
}


output "all_nodes" {
  description = "Combined map of all nodes for inventory generation"
  value       = module.vm.all_nodes
}

