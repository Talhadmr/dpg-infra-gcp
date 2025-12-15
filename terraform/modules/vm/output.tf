output "nodes" {
  value = {
    for v in google_compute_instance.vm :
    v.name => {
      ip   = v.network_interface[0].network_ip
      role = startswith(v.name, "master-") ? "control" : startswith(v.name, "worker-") ? "worker" : "other"
    }
  }
}