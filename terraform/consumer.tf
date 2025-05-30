resource "google_compute_instance" "clients" {
  count        = 2
  name         = "${local.prefix}cli${count.index + 1}${local.suffix}"
  machine_type = "e2-micro"

  boot_disk {
    initialize_params {
      image = "ubuntu-os-cloud/ubuntu-2404-lts-amd64"
    }
  }
  network_interface {
    subnetwork = one(module.consumer_net.subnets_ids)
  }
}

module "consumer_net" {
  source  = "terraform-google-modules/network/google"
  version = "~> 10.0"

  project_id   = var.project_id
  network_name = "${local.prefix}consumer${local.suffix}"
  routing_mode = "GLOBAL"

  subnets = [{
    subnet_name   = "${local.prefix}cons${local.suffix}"
    subnet_ip     = var.cidr_consumer
    subnet_region = local.region
  }]

  ingress_rules = [{
    name          = "${local.prefix}cons-iap-ssh${local.suffix}"
    source_ranges = ["35.235.240.0/20"]
    allow = [{
      protocol = "tcp"
      ports    = ["22"]
    }]
  }]
}

# Connect VPC to NSI as consumer

resource "google_network_security_intercept_endpoint_group_association" "consumer" {
  provider                                = google-beta
  intercept_endpoint_group_association_id = "${local.prefix}iega${local.suffix}"
  location                                = "global"
  network                                 = module.consumer_net.network_id
  intercept_endpoint_group                = google_network_security_intercept_endpoint_group.consumer.id
}

resource "google_network_security_intercept_endpoint_group" "consumer" {
  provider                    = google-beta
  intercept_endpoint_group_id = "${local.prefix}ieg${local.suffix}"
  location                    = "global"
  intercept_deployment_group  = google_network_security_intercept_deployment_group.producer.id
  description                 = "NSI consumer endpoint group"
}

# Create organization-wide security profile for use in firewall policy

resource "google_network_security_security_profile_group" "consumer" {
  provider                 = google-beta
  name                     = "${local.prefix}spg${local.suffix}"
  parent                   = "organizations/${var.organization_id}"
  custom_intercept_profile = google_network_security_security_profile.consumer.id
}

resource "google_network_security_security_profile" "consumer" {
  provider = google-beta
  name     = "${local.prefix}sp${local.suffix}"
  parent   = "organizations/${var.organization_id}"
  type     = "CUSTOM_INTERCEPT"

  custom_intercept_profile {
    intercept_endpoint_group = google_network_security_intercept_endpoint_group.consumer.id
  }
}


resource "google_compute_network_firewall_policy_with_rules" "nsi_scan" {
  provider = google-beta
  name     = "${local.prefix}fpol${local.suffix}"

  rule {
    action                 = "apply_security_profile_group"
    direction              = "INGRESS"
    disabled               = false
    enable_logging         = false
    security_profile_group = google_network_security_security_profile_group.consumer.id
    priority               = 100
    rule_name              = "${local.prefix}intercept-ingress${local.suffix}"

    match {
      src_ip_ranges = [var.cidr_consumer]

      layer4_config {
        ip_protocol = "all"
      }
    }
  }

  rule {
    action                 = "apply_security_profile_group"
    direction              = "EGRESS"
    disabled               = true
    enable_logging         = false
    security_profile_group = google_network_security_security_profile_group.consumer.id
    priority               = 101
    rule_name              = "${local.prefix}intercept-egress${local.suffix}"

    match {
      dest_ip_ranges = [var.cidr_consumer]

      layer4_config {
        ip_protocol = "all"
      }
    }
  }
}

resource "google_compute_network_firewall_policy_association" "consumer" {
  name              = "${local.prefix}fpol${local.suffix}"
  attachment_target = module.consumer_net.network_id
  firewall_policy   = google_compute_network_firewall_policy_with_rules.nsi_scan.id
}

