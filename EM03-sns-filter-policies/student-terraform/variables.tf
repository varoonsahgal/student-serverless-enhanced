variable "region" {
  type    = string
  default = "us-west-2"
}

variable "course_prefix" {
  type    = string
  default = "acme"
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
