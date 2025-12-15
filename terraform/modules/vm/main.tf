resource "google_compute_instance" "vm" {
  count        = var.instance_count
  name         = count.index < var.master_count ? format("master-%02d", count.index + 1) : format("worker-%02d", count.index - var.master_count + 1)
  zone         = var.zone
  machine_type = var.machine_type
  tags         = ["iap-ssh"]

  boot_disk {
    initialize_params {
      image = var.image
      size  = var.boot_disk_gb
      type  = "pd-standard"
    }
  }

  network_interface {
    subnetwork = var.subnetwork
  }
}