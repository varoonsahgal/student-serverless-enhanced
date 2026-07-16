variable "region" {
  type        = string
  description = "AWS region."
  default     = "us-west-2"
}

variable "course_prefix" {
  type        = string
  description = "Short run identifier used in all resource names, e.g. 'acme'."
  default     = "acme"
  validation {
    condition     = can(regex("^[a-z0-9-]{2,20}$", var.course_prefix))
    error_message = "course_prefix: 2-20 lowercase alphanumeric chars or hyphens."
  }
}

variable "student_id" {
  type        = string
  description = "Your unique identifier (e.g. your name/initials plus a random suffix, like \"jsmith42\"). Prefixes every resource this stack creates so it can never collide with a classmate's resources in the same shared account. There is no default on purpose -- you must set this."
  validation {
    condition     = can(regex("^[a-z0-9-]{3,20}$", var.student_id))
    error_message = "student_id must be 3-20 lowercase letters, digits, or hyphens (e.g. \"jsmith42\")."
  }
}

variable "log_retention_days" {
  type        = number
  description = "CloudWatch Logs retention (days)."
  default     = 7
  validation {
    condition     = contains([1, 3, 5, 7, 14, 30], var.log_retention_days)
    error_message = "log_retention_days must be one of 1, 3, 5, 7, 14, 30."
  }
}
