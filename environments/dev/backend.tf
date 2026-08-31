# Remote state backend.
# Why: keeps the .tfstate file in S3 (not on a laptop) so state is shared
# safely, and DynamoDB provides a lock so two "terraform apply" runs can't
# collide and corrupt state.
#
# NOTE: the S3 bucket and DynamoDB table below must already exist before
# this backend can be used - Terraform can't create the backend it's about
# to store its own state in. Create them once, manually or via a separate
# small "bootstrap" Terraform config, then fill in the names below.

terraform {
  backend "s3" {
    bucket         = "cribl-project-tfstate-charan01"   # must be globally unique
    key            = "dev/terraform.tfstate"
    region         = "ap-south-1"
    dynamodb_table = "cribl-project-tf-locks"
    encrypt        = true
  }
}
