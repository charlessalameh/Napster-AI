variable "subscription_id" {
  description = "Azure subscription ID to deploy into (az account show --query id -o tsv)."
  type        = string
}

variable "location" {
  description = "Azure region for the state storage."
  type        = string
  default     = "swedencentral"
}

variable "name_prefix" {
  description = "Short lowercase prefix (letters/digits, max 10) used in resource names."
  type        = string
  default     = "schooldemo"

  validation {
    condition     = can(regex("^[a-z0-9]{3,10}$", var.name_prefix))
    error_message = "name_prefix must be 3-10 lowercase letters or digits."
  }
}

variable "tags" {
  description = "Tags applied to all resources."
  type        = map(string)
  default = {
    project = "school-agent-demo"
    purpose = "terraform-state"
  }
}
