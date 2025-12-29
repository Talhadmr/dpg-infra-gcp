variable "project_name" {
  description = "Project name prefix for resource naming"
  type        = string
}

variable "region" {
  description = "GCP region for the VPC"
  type        = string
}

variable "subnet_cidr" {
  description = "CIDR block for the subnet"
  type        = string
  default     = "10.10.10.0/24"
}

variable "enable_nat" {
  description = "Enable Cloud NAT for outbound internet access"
  type        = bool
  default     = true
}

variable "enable_iap_ssh" {
  description = "Enable IAP SSH firewall rule"
  type        = bool
  default     = true
}
