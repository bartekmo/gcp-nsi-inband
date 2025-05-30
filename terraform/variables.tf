variable "zone" {
  type        = string
  description = "Indicate zone where to deploy consumer and producer"
  default     = "europe-west1-b"
}

variable "project_id" {
  type        = string
  description = "Project to deploy consumer and producer to"
}

variable "organization_id" {
  type        = string
  description = "Indicate organization id for linking security profile"
}

variable "prefix" {
  type        = string
  description = "This prefix will be prepended to names of all created resources"
  default     = ""
}

variable "suffix" {
  type        = string
  description = "Suffix to be added to names of all resources. Set to RANDOM to get a random 3-letter suffix generated at terraform plan"
  default     = ""
}

variable "labels" {
  type        = map(string)
  description = "These labels will be added to all created resources"
  default     = {}
}

variable "cidr_producer" {
  type        = string
  description = "CIDR for producer subnet"
  default     = "10.255.0.0/24"
}

variable "cidr_consumer" {
  type        = string
  description = "CIDR for consumer subnet"
  default     = "192.168.0.0/24"
}
