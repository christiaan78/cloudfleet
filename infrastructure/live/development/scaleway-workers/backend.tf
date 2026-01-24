terraform {
  cloud {
    organization = "cloudlab-christiaan"

    workspaces {
      name = "development-scaleway-workers"
    }
  }
}
