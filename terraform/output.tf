output "all_nodes" {
  description = "Exposing the nodes from the vm module to the CLI"
  value       = module.vm.nodes
}