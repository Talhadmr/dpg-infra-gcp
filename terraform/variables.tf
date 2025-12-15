variable "project_id" {
  type    = string
  default = "dpg-project-481018 "
}

variable "region" {
  type    = string
  default = "europe-west3"
}

variable "k8s-vms" {
  type = object({
    master_count = number
    worker_count = number
  })

  default = {
    master_count = 3
    worker_count = 3
  }
}
