variable "serverName" {
  type   = string
}

# EC2 Instance Resource
# This resource creates an EC2 instance in AWS.
# More information about the aws_instance resource can be found here: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/instance
resource "aws_instance" "ec2" {
  ami = "ami-00f46ccd1cbfb363e"
  instance_type = "t2.micro"
  security_groups = [module.SG.sg_name  ]
  tags = {
      Name = var.serverName 
  }
    user_data = file("server-script.sh") # Alternative way to provide user data from a file
}

module "EIP" {
  source = "../eip"
  instanceID = aws_instance.ec2.id
  }
  

module "SG" {
  source = "../sg"
}

output "EIP-private_ip" {
  value = module.EIP.EIP-private_ip
} 

output "EIP-public_ip" {
  value = module.EIP.EIP-public_ip
} 


