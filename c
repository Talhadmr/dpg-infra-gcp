variable "project_id" {
  type    = string
  default = "dpg-project-481018"
}

variable "region" {
  type    = string
  default = "europe-west3"
}

variable "zone" {
  type    = string
  default = "europe-west3-a"
}

variable "vm_name" {
  type = string
}

variable "vm_tags" {
  type    = list(string)
  default = ["iap-ssh"]
}

variable "subnetwork" {
  type = string
}

variable "instance_count" {
  type    = number
  default = 6
}

variable "master_count" {
  type    = number
  default = 3
}

variable "machine_type" {
  type    = string
  default = "e2-standard-2"
}

variable "boot_disk_type" {
  type    = string
  default = "pd-standard"
}

variable "boot_disk_gb" {
  type    = number
  default = 10
}

variable "enable_public_ip" {
  type    = bool
  default = false
}

variable "image" {
  type    = string
  default = "projects/debian-cloud/global/images/family/debian-12"
}
