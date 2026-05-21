variable "location" {
  description = "Azure region for all resources."
  type        = string
  default     = "centralus"
}

variable "project_name" {
  description = "Short name used as a prefix for resource names."
  type        = string
  default     = "gohello"
}

variable "environment" {
  description = "Deployment environment (e.g. dev, prod)."
  type        = string
  default     = "dev"
}
