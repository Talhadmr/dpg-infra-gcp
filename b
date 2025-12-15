resource "google_compute_instance" "vm" {
  count        = var.instance_count
  name         = var.vm_name
  zone         = var.zone
  machine_type = var.machine_type
  tags         = var.vm_tags

  boot_disk {
    initialize_params {
      image = var.image
      size  = var.boot_disk_gb
      type  = var.boot_disk_type
    }
  }

  network_interface {
    subnetwork = var.subnetwork
  }
}
