terraform {
  required_version = "= 1.14.2"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "= 7.13.0"
    }
  }
}

provider "google" {
  project = trimspace(var.project_id)
  region  = var.region
  impersonate_service_account = "tf-lab@dpg-project-481018.iam.gserviceaccount.com"
}
