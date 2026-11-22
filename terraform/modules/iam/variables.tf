variable "name" {
  type = string
}

variable "allowed_regions" {
  description = "Regions IAM principals may operate in"
  type        = list(string)
  default     = ["ca-central-1", "ca-west-1"]
}

variable "data_bucket_arn" {
  description = "Bucket holding client data the DataEngineer group may read"
  type        = string
}

variable "kms_key_arn" {
  type = string
}

variable "cloudtrail_bucket" {
  description = "Existing bucket for CloudTrail (usually in a log-archive account). Empty disables the trail."
  type        = string
  default     = ""
}

variable "tags" {
  type    = map(string)
  default = {}
}
