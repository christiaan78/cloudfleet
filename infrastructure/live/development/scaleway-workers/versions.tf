terraform {
  required_version = ">= 1.5.0"

  required_providers {
    cloudfleet = {
      source  = "terraform.cloudfleet.ai/cloudfleet/cloudfleet"
      version = ">= 0.1.0"
    }
    scaleway = {
      source  = "scaleway/scaleway"
      version = ">= 2.0.0"
    }
  }
}
