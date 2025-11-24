
provider "aws" {
    region = "us-west-2"
}

module "ec2" {  
  source = "./ec2"
  server_name = ["EC2-1", "EC2-2", "EC2-3"]
}


output "private_ips_of_ec2_instances" {
  value = module.ec2.private_ips
} 