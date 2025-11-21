
#  Provider Configuration 
# This can be used to configure the AWS provider, AZURe provider, GCP provider, and so on.
# More information about provider configuration can be found here:
# https://registry.terraform.io/providers/hashicorp/aws/latest/docs#configuration

provider "aws" {
    region = "us-west-2"
    profile = var.aws_profile
}
# Resource Definition
# This block defines an AWS VPC resource with a specified CIDR block.
# More information about AWS VPC resource can be found here:
# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc


resource "aws_vpc" "myvpc" {
  cidr_block = "10.0.0.0/16"
}
