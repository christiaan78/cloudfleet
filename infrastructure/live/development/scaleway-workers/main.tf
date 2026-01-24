provider "cloudfleet" {}
provider "scaleway" {}

data "cloudfleet_cfke_cluster" "cluster" {
  id = var.cfke_cluster_id
}

resource "cloudfleet_cfke_node_join_information" "scaleway" {
  cluster_id = data.cloudfleet_cfke_cluster.cluster.id
  region     = var.scaleway_region
  zone       = var.scaleway_zone

  node_labels = {
    "cfke.io/provider" = "scaleway"
  }

  # Scaleway requires uncompressed userdata
  base64_encode = false
  gzip          = false
}

resource "scaleway_instance_server" "worker" {
  count = var.worker_count

  name  = "cfke-scaleway-worker-${count.index + 1}"
  type  = var.worker_type
  image = var.worker_image

  user_data = {
    cloud-init = cloudfleet_cfke_node_join_information.scaleway.rendered
  }

  enable_dynamic_ip = true
}
