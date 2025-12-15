output "cluster_nodes" {
  description = "Map of cluster nodes with their details (for Kubespray inventory)"
  value = {
    for name, instance in google_compute_instance.cluster :
    name => {
      ip   = instance.network_interface[0].network_ip
      role = local.cluster_nodes[name].role
      zone = instance.zone
    }
  }
}

output "master_nodes" {
  description = "Map of master nodes only"
  value = {
    for name, instance in google_compute_instance.cluster :
    name => {
      ip   = instance.network_interface[0].network_ip
      zone = instance.zone
    } if local.cluster_nodes[name].role == "control"
  }
}

output "worker_nodes" {
  description = "Map of worker nodes only"
  value = {
    for name, instance in google_compute_instance.cluster :
    name => {
      ip   = instance.network_interface[0].network_ip
      zone = instance.zone
    } if local.cluster_nodes[name].role == "worker"
  }
}

output "standalone_nodes" {
  description = "Map of standalone VMs with their details"
  value = {
    for name, instance in google_compute_instance.standalone :
    name => {
      ip   = instance.network_interface[0].network_ip
      zone = instance.zone
    }
  }
}

output "all_nodes" {
  description = "Combined map of all nodes (cluster + standalone) for inventory generation"
  value = merge(
    {
      for name, instance in google_compute_instance.cluster :
      name => {
        ip   = instance.network_interface[0].network_ip
        role = local.cluster_nodes[name].role
      }
    },
    {
      for name, instance in google_compute_instance.standalone :
      name => {
        ip   = instance.network_interface[0].network_ip
        role = "standalone"
      }
    }
  )
}

output "cluster_node_ips" {
  description = "List of all cluster node IPs"
  value       = [for instance in google_compute_instance.cluster : instance.network_interface[0].network_ip]
}

output "standalone_node_ips" {
  description = "List of all standalone VM IPs"
  value       = [for instance in google_compute_instance.standalone : instance.network_interface[0].network_ip]
}

