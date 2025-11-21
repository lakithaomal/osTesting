

terraform {
  backend "s3" {
    key = "terraform/tfstate.tfstate"
    bucket = "os-s3-backups"
    region = "us-west-2"
}
}
