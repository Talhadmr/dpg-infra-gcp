variable "project_id" {
  description = "GCP Project ID"
  type        = string
}

variable "region" {
  description = "GCP region"
  type        = string
  default     = "europe-west3"
}

variable "zone" {
  description = "GCP zone"
  type        = string
  default     = "europe-west3-a"
}


variable "vpc_config" {
  description = "VPC network configuration"
  type = object({
    name           = string
    subnet_cidr    = string
    enable_nat     = bool
    enable_iap_ssh = bool
  })
  default = {
    name           = "dpg-lab"
    subnet_cidr    = "10.10.10.0/24"
    enable_nat     = true
    enable_iap_ssh = true
  }
}


variable "cluster_nodes" {
  description = "Configuration for Kubernetes cluster nodes"
  type = object({
    enabled             = bool
    master_count        = number
    worker_count        = number
    master_machine_type = string
    worker_machine_type = string
    master_disk_size_gb = number
    worker_disk_size_gb = number
    disk_type           = string
    image               = string
  })
  default = {
    enabled             = true
    master_count        = 3
    worker_count        = 2
    master_machine_type = "e2-standard-2"
    worker_machine_type = "e2-standard-4"
    master_disk_size_gb = 30
    worker_disk_size_gb = 50
    disk_type           = "pd-balanced"
    image               = "projects/debian-cloud/global/images/family/debian-12"
  }
}


variable "standalone_vms" {
  description = "List of standalone VMs outside the Kubernetes cluster"
  type = list(object({
    name         = string
    machine_type = optional(string)
    disk_size_gb = optional(number)
    disk_type    = optional(string)
    image        = optional(string)
    tags         = optional(list(string))
    labels       = optional(map(string))
    public_ip    = optional(bool, false)
  }))
  default = []
}

variable "standalone_defaults" {
  description = "Default values for standalone VMs"
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

variable "common_tags" {
  description = "Common network tags to apply to all VMs"
  type        = list(string)
  default     = ["iap-ssh"]
}

variable "common_labels" {
  description = "Common labels to apply to all VMs"
  type        = map(string)
  default = {
    managed_by = "terraform"
    project    = "dpg-lab"
  }
}
