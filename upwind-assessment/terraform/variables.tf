variable "region" {
  description = "AWS region to deploy the lab into."
  type        = string
  default     = "us-east-1"
}

variable "cluster_name" {
  description = "Name of the EKS cluster."
  type        = string
  default     = "upwind-lab"
}

variable "kubernetes_version" {
  description = "EKS control plane version."
  type        = string
  default     = "1.31"
}

variable "vpc_cidr" {
  description = "CIDR block for the lab VPC."
  type        = string
  default     = "10.0.0.0/16"
}

variable "node_instance_type" {
  description = "Instance type for the managed node group."
  type        = string
  default     = "t3.medium"
}

variable "node_desired_size" {
  description = "Desired number of worker nodes."
  type        = number
  default     = 2
}

# Lock the Kubernetes API endpoint to your IP for the demo. Find yours with:
#   curl -s https://checkip.amazonaws.com
# then set this, e.g. TF_VAR_admin_cidr="203.0.113.5/32".
variable "admin_cidr" {
  description = "CIDR allowed to reach the public EKS API endpoint. Default is wide open for lab convenience — override it."
  type        = string
  default     = "0.0.0.0/0"
}

variable "tags" {
  description = "Tags applied to all resources."
  type        = map(string)
  default = {
    Project = "upwind-sa-assessment"
    Owner   = "trwilson"
    Env     = "lab"
  }
}
