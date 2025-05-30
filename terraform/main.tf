locals {
  #derive region from zone variable
  region = join("-", slice(split("-", var.zone), 0, 2))

  #sanitize labels
  labels = { for k, v in var.labels : k => replace(lower(v), " ", "_") }

  # If prefix is defined, add a "-" spacer after it
  prefix = length(var.prefix) > 0 && substr(var.prefix, -1, 1) != "-" ? "${var.prefix}-" : var.prefix

  # generate random suffix if requested and prepen with "-"
  # NOTE: random suffix is not compatible with google's network module (https://github.com/terraform-google-modules/terraform-google-network/issues/620)
  suffix_raw = var.suffix // == "RANDOM" ? random_string.random_suffix.result : var.suffix
  suffix     = length(local.suffix_raw) > 0 && substr(local.suffix_raw, 0, 1) != "-" ? "-${local.suffix_raw}" : local.suffix_raw

  # use ssh for health check
  hc_port = 22
}

resource "random_string" "random_suffix" {
  length  = 3
  special = false
  upper   = false
}


