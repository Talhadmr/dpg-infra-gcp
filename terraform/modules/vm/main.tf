locals {
  # Generate master node names: master-01, master-02, master-03...
  master_nodes = var.cluster_nodes.enabled ? {
    for i in range(var.cluster_nodes.master_count) :
    format("master-%02d", i + 1) => {
      role         = "control"
      machine_type = var.cluster_nodes.machine_type
      disk_size_gb = var.cluster_nodes.disk_size_gb
      disk_type    = var.cluster_nodes.disk_type
      image        = var.cluster_nodes.image
    }
  } : {}

  # Generate worker node names: worker-01, worker-02, worker-03...
  worker_nodes = var.cluster_nodes.enabled ? {
    for i in range(var.cluster_nodes.worker_count) :
    format("worker-%02d", i + 1) => {
      role         = "worker"
      machine_type = var.cluster_nodes.machine_type
      disk_size_gb = var.cluster_nodes.disk_size_gb
      disk_type    = var.cluster_nodes.disk_type
      image        = var.cluster_nodes.image
    }
  } : {}

  cluster_nodes = merge(local.master_nodes, local.worker_nodes)

  #standalone VMs
  standalone_nodes = {
    for vm in var.standalone_vms :
    vm.name => {
      role         = "standalone"
      machine_type = coalesce(vm.machine_type, var.standalone_defaults.machine_type)
      disk_size_gb = coalesce(vm.disk_size_gb, var.standalone_defaults.disk_size_gb)
      disk_type    = coalesce(vm.disk_type, var.standalone_defaults.disk_type)
      image        = coalesce(vm.image, var.standalone_defaults.image)
      tags         = coalesce(vm.tags, var.tags)
      labels       = coalesce(vm.labels, var.labels)
      public_ip    = coalesce(vm.public_ip, false)
    }
  }
}

resource "google_compute_instance" "cluster" {
  for_each = local.cluster_nodes

  name         = each.key
  zone         = var.zone
  machine_type = each.value.machine_type
  tags         = var.tags
  labels = merge(var.labels, {
    role    = each.value.role
    cluster = "kubernetes"
  })

  boot_disk {
    initialize_params {
      image = each.value.image
      size  = each.value.disk_size_gb
      type  = each.value.disk_type
    }
  }

  network_interface {
    subnetwork = var.subnetwork
  }

  metadata = {
    enable-oslogin = "TRUE"
  }

  lifecycle {
    ignore_changes = [
      metadata["ssh-keys"]
    ]
  }
}

# Static IP for bastion 
resource "google_compute_address" "bastion" {
  count  = contains([for vm in var.standalone_vms : vm.name], "bastion") ? 1 : 0
  name   = "bastion-ip"
  region = var.region
}

resource "google_compute_instance" "standalone" {
  for_each = local.standalone_nodes

  name         = each.key
  zone         = var.zone
  machine_type = each.value.machine_type
  tags         = each.value.tags
  labels = merge(each.value.labels, {
    role = "standalone"
  })

  boot_disk {
    initialize_params {
      image = each.value.image
      size  = each.value.disk_size_gb
      type  = each.value.disk_type
    }
  }

  network_interface {
    subnetwork = var.subnetwork

    dynamic "access_config" {
      for_each = each.value.public_ip ? [1] : []
      content {
        # Use static IP for bastion, ephemeral for others
        nat_ip = each.key == "bastion" ? google_compute_address.bastion[0].address : null
      }
    }
  }

  metadata = {
    enable-oslogin = "TRUE"
  }

  lifecycle {
    ignore_changes = [
      metadata["ssh-keys"]
    ]
  }
}
