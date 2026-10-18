terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      # aws_bedrockagentcore_harness requires 6.46.0+
      version = ">= 6.46.0"
    }
    archive = {
      source = "hashicorp/archive"
    }
  }

  required_version = "~> 1.6"
}
