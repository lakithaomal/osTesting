
#  Provider Configuration 
# This can be used to configure the AWS provider, AZURe provider, GCP provider, and so on.
# More information about provider configuration can be found here:
# https://registry.terraform.io/providers/hashicorp/aws/latest/docs#configuration

provider "aws" {
    region = "us-west-2"
    profile = var.aws_profile
}

module "DBServer" {
  source = "./dbServer"
  serverName = "DB"
}


module "webServer" {
  source = "./webServer"
  serverName = "Web Server"
}


 # Output the Elastic IP 
# This output displays the public IP address of the allocated Elastic IP.
# More information about outputs can be found here: https://www.terraform.io/language/values/outputs
output "DBServer-EIP-private_ip" {
  value = module.DBServer.EIP-private_ip
} 

output "DBServer-EIP-public_ip" {
  value = module.DBServer.EIP-public_ip
} 


output "webServer-EIP-private_ip" {
  value = module.webServer.EIP-private_ip
} 

output "webServer-EIP-public_ip" {
  value = module.webServer.EIP-public_ip
} 


data "aws_instance" "db_instance" {
 filter {
  name   = "tag:Name"
  values = ["DB"] 
 }
}


output "DB_instance_id" {
  value = data.aws_instance.db_instance.id    
}


