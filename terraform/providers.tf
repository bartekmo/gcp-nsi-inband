terraform {
  required_providers {
    google = {
      source = "hashicorp/google"
    }
    google-beta = {
      source = "hashicorp/google-beta"
    }
  }
}

provider "google" {
  project        = var.project_id
  region         = local.region
  zone           = var.zone
  default_labels = var.labels
}

provider "google-beta" {
  project               = var.project_id
  region                = local.region
  zone                  = var.zone
  default_labels        = var.labels
  user_project_override = true
  billing_project       = var.project_id
}
