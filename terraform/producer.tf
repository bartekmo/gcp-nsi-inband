module "producer_net" {
  source  = "terraform-google-modules/network/google"
  version = "~> 10.0"

  project_id   = var.project_id
  network_name = "${local.prefix}prod${local.suffix}"
  routing_mode = "GLOBAL"

  subnets = [{
    subnet_name           = "${local.prefix}prod${local.suffix}"
    subnet_ip             = var.cidr_producer
    subnet_region         = local.region
    subnet_private_access = "true"
  }]

  ingress_rules = [{
    name          = "${local.prefix}prod-iap-ssh${local.suffix}"
    source_ranges = ["35.235.240.0/20"]
    allow = [{
      protocol = "tcp"
      ports    = ["22"]
    }]
    },
    {
      name          = "${local.prefix}prod-geneve${local.suffix}"
      source_ranges = ["${cidrhost(var.cidr_producer, 1)}/32"]
      allow = [{
        protocol = "udp"
        ports    = ["6081"]
      }]
    },
    {
      name          = "${local.prefix}prod-health${local.suffix}"
      source_ranges = ["35.191.0.0/16", "130.211.0.0/22"]
      allow = [{
        protocol = "tcp"
        ports    = [local.hc_port]
      }]
  }]
}

resource "google_compute_instance_template" "nva" {
  machine_type = "e2-standard-2"

  network_interface {
    subnetwork = one(module.producer_net.subnets_ids)
  }
  disk {
    source_image = "ubuntu-os-cloud/ubuntu-2404-lts-amd64"
    auto_delete  = true
    boot         = true
  }

  metadata_startup_script = <<EOF
tc qdisc add dev ens4 ingress
tc filter add dev ens4 parent ffff: protocol ip prio 1 u32 \
  match ip dst ${google_compute_address.nsi_ilb.address}/32 \
  match ip src ${cidrhost(var.cidr_producer, 1)}/32 \
  match ip dport 6081 0xffff \
  action nat ingress ${google_compute_address.nsi_ilb.address}/32 ${cidrhost(var.cidr_producer, 1)} \
  action nat egress ${cidrhost(var.cidr_producer, 1)}/32 ${google_compute_address.nsi_ilb.address}
  EOF
}

resource "google_compute_instance_group_manager" "nvas" {
  name               = "${local.prefix}nva${local.suffix}"
  base_instance_name = "${local.prefix}nva${local.suffix}"
  zone               = var.zone
  version {
    instance_template = google_compute_instance_template.nva.id
  }
  target_size = 1
}

####### Internal Load Balancer ######################

resource "google_compute_region_health_check" "ssh" {
  name = "${local.prefix}nsiilb-hc-ssh${local.suffix}"
  tcp_health_check {
    port = local.hc_port
  }
}

resource "google_compute_region_backend_service" "nsi_ilb" {
  name     = "${local.prefix}nsiilb-bes${local.suffix}"
  region   = local.region
  network  = module.producer_net.network_id
  protocol = "UDP"

  backend {
    group          = google_compute_instance_group_manager.nvas.instance_group
    balancing_mode = "CONNECTION"
  }
  health_checks = [google_compute_region_health_check.ssh.self_link]
}

resource "google_compute_address" "nsi_ilb" {
  name         = "${local.prefix}nsiilb-addr${local.suffix}"
  subnetwork   = one(module.producer_net.subnets_ids)
  region       = local.region
  address_type = "INTERNAL"
}

resource "google_compute_forwarding_rule" "nsi_ilb" {
  name                  = "${local.prefix}nsiilb-fr${local.suffix}"
  region                = local.region
  load_balancing_scheme = "INTERNAL"
  ip_address            = google_compute_address.nsi_ilb.address
  ip_protocol           = "UDP"
  ports                 = ["6081"]
  backend_service       = google_compute_region_backend_service.nsi_ilb.id
  network               = module.producer_net.network_id
  subnetwork            = one(module.producer_net.subnets_ids)
  allow_global_access   = false
}

########## NSI ########################

resource "google_network_security_intercept_deployment_group" "producer" {
  provider                      = google-beta
  intercept_deployment_group_id = "${local.prefix}idg${local.suffix}"
  location                      = "global"
  network                       = module.producer_net.network_id
}

resource "google_network_security_intercept_deployment" "producer" {
  provider                   = google-beta
  intercept_deployment_id    = "${local.prefix}id${local.suffix}"
  location                   = var.zone
  forwarding_rule            = google_compute_forwarding_rule.nsi_ilb.id
  intercept_deployment_group = google_network_security_intercept_deployment_group.producer.id
}
