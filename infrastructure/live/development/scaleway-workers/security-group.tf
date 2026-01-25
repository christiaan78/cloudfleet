resource "scaleway_instance_security_group" "cfke_worker" {
  name                    = "cfke-worker-sg"
  zone                    = var.scaleway_zone
  stateful                = true
  inbound_default_policy  = "drop"
  outbound_default_policy = "accept"

}
