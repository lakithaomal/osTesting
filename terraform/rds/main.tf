
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

resource aws_db_instance "rds_instance" {
  allocated_storage    = 100
  identifier 		   = "my-postgres-db"  
  storage_type         = "gp2"
  engine               = "postgres"
  engine_version       = "18.1"
  instance_class       = "db.m5d.large"
  db_name              = "OS1"
  username             = "PostgresUser"
  password             = "PostgresPassword"
  port 				   = 5432
  skip_final_snapshot  = true
}