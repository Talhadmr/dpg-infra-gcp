variable "subnetwork" {
  description = "The subnetwork self link to attach VMs"
  type        = string
}

variable "zone" {
  description = "GCP zone for the VMs"
  type        = string
}

variable "tags" {
  description = "Network tags to apply to all VMs"
  type        = list(string)
  default     = ["iap-ssh"]
}

variable "labels" {
  description = "Labels to apply to all VMs"
  type        = map(string)
  default     = {}
}

variable "cluster_nodes" {
  description = "Configuration for Kubernetes cluster nodes (masters and workers)"
  type = object({
    enabled      = bool
    master_count = number
    worker_count = number
    machine_type = string
    disk_size_gb = number
    disk_type    = string
    image        = string
  })
  default = {
    enabled      = false
    master_count = 0
    worker_count = 0
    machine_type = "e2-standard-2"
    disk_size_gb = 20
    disk_type    = "pd-standard"
    image        = "projects/debian-cloud/global/images/family/debian-12"
  }
}

variable "standalone_vms" {
  description = "List of standalone VMs with custom names and optional overrides"
  type = list(object({
    name         = string
    machine_type = optional(string)
    disk_size_gb = optional(number)
    disk_type    = optional(string)
    image        = optional(string)
    tags         = optional(list(string))
    labels       = optional(map(string))
  }))
  default = []
}

variable "standalone_defaults" {
  description = "Default values for standalone VMs (used when not overridden per VM)"
  type = object({
    machine_type = string
    disk_size_gb = number
    disk_type    = string
    image        = string
  })
  default = {
    machine_type = "e2-medium"
    disk_size_gb = 20
    disk_type    = "pd-standard"
    image        = "projects/debian-cloud/global/images/family/debian-12"
  }
}
