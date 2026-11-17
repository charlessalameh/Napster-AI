variable "subscription_id" {
  description = "Azure subscription ID."
  type        = string
}

variable "location" {
  description = "Azure region. Must offer the chat model and the embedding model below."
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

# --- Models (check Microsoft Learn "Foundry Models sold by Azure" before changing) ---

variable "chat_model_name" {
  description = "Azure OpenAI chat model. gpt-4.1-mini is non-reasoning, so replies are fast enough for voice."
  type        = string
  default     = "gpt-4.1-mini"
}

variable "chat_model_version" {
  type    = string
  default = "2025-04-14"
}

variable "chat_deployment_name" {
  description = "Deployment name the app calls."
  type        = string
  default     = "chat"
}

variable "chat_capacity" {
  description = "Chat capacity in thousands of tokens per minute (30 = 30K TPM). Keep small for cost."
  type        = number
  default     = 30
}

variable "embedding_model_name" {
  type    = string
  default = "text-embedding-3-small"
}

variable "embedding_model_version" {
  type    = string
  default = "1"
}

variable "embedding_deployment_name" {
  type    = string
  default = "embedding"
}

variable "embedding_capacity" {
  description = "Embedding capacity in thousands of tokens per minute."
  type        = number
  default     = 30
}

variable "model_sku" {
  description = "Deployment SKU: GlobalStandard (widest availability) or Standard (data stays in region)."
  type        = string
  default     = "GlobalStandard"
}

# --- SKUs ---

variable "search_sku" {
  description = "AI Search SKU. basic supports semantic/vector and managed identity; free has limits (no managed identity to storage)."
  type        = string
  default     = "basic"
}

variable "app_service_sku" {
  type    = string
  default = "B1"
}

variable "search_index_name" {
  type    = string
  default = "school"
}

variable "docs_container_name" {
  type    = string
  default = "school-docs"
}

variable "tags" {
  type = map(string)
  default = {
    project = "school-agent-demo"
  }
}
