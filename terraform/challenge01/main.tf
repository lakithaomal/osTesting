
#  Provider Configuration 
# This can be used to configure the AWS provider, AZURe provider, GCP provider, and so on.
# More information about provider configuration can be found here:
# https://registry.terraform.io/providers/hashicorp/aws/latest/docs#configuration

provider "aws" {
    region = "us-west-2"
}

# Resource Definition
# This block defines an AWS VPC resource with a specified CIDR block.
# More information about AWS VPC resource can be found here:
# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc

# Create an AWS VPC with a CIDR block of 10.0.0.0/16    
#  my_first_vpc is the name given to this resource instance.
resource "aws_vpc" "myvpc" {
  cidr_block = "192.168.0.0/16"
  tags = {
    Name = "TerraformVPC"
  }
}
