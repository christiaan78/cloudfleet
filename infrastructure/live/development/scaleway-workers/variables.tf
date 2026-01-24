variable "cfke_cluster_id" { type = string }

variable "scaleway_region" {
  type    = string
  default = "fr-par"
}

variable "scaleway_zone" {
  type    = string
  default = "fr-par-1"
}

variable "worker_type" {
  type    = string
  default = "DEV1-M"
}

variable "worker_image" {
  type    = string
  default = "ubuntu_jammy"
}

variable "worker_count" {
  type    = number
  default = 1
}
