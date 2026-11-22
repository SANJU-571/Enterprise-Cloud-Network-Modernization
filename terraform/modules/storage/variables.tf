variable "name" {
  type = string
}

variable "kms_key_arn" {
  description = "KMS key in the primary region"
  type        = string
}

variable "dr_kms_key_arn" {
  description = "KMS key in the DR region (replica encryption)"
  type        = string
}

variable "object_lock_days" {
  description = "Default Object Lock retention (ransomware protection for backups)"
  type        = number
  default     = 30
}

variable "tags" {
  type    = map(string)
  default = {}
}
