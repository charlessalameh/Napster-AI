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

# --- Optional hardening (both off by default; see README "Hardening") ---

variable "enable_private_networking" {
  description = "VNet integration for the web app + Private Endpoints for OpenAI, Search and Storage."
  type        = bool
  default     = false
}

variable "vnet_cidr" {
  description = "Address space of the VNet (used only when enable_private_networking is true)."
  type        = string
  default     = "10.20.0.0/16"
}

variable "enable_easy_auth" {
  description = "Require Entra ID sign-in for the whole web app. Run scripts/setup-easyauth.sh first."
  type        = bool
  default     = false
}

variable "easy_auth_client_id" {
  description = "Client ID of the Entra app registration (printed by scripts/setup-easyauth.sh)."
  type        = string
  default     = ""
}

variable "easy_auth_identity_id" {
  description = "Resource ID of the persistent user-assigned identity from infra/bootstrap-state."
  type        = string
  default     = ""
}

variable "easy_auth_identity_client_id" {
  description = "Client ID of that user-assigned identity."
  type        = string
  default     = ""
}

# --- Optional voice: ElevenLabs text-to-speech (off while key_vault_name is empty) ---
# The API key itself is NOT a Terraform value. You put it in the Key Vault by hand, and the
# web app reads it there with its managed identity (a Key Vault reference in its settings).

variable "key_vault_name" {
  description = "Name of the Key Vault (from infra/bootstrap-state) that holds the ElevenLabs key. Empty = voice off."
  type        = string
  default     = ""
}

variable "key_vault_resource_group" {
  description = "Resource group of that Key Vault. Empty = the bootstrap group, <name_prefix>-tfstate-rg."
  type        = string
  default     = ""
}

variable "key_vault_secret_name" {
  description = "Name of the secret that holds the ElevenLabs API key."
  type        = string
  default     = "elevenlabs-api-key"
}

variable "elevenlabs_voice_id" {
  description = "ElevenLabs voice ID (not a secret)."
  type        = string
  default     = ""
}

variable "elevenlabs_model_id" {
  description = "ElevenLabs model. Empty = eleven_multilingual_v2 (Arabic, English, French)."
  type        = string
  default     = ""
}
