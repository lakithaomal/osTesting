
variable "serverName" {
  type   = string
}

# EC2 Instance Resource
# This resource creates an EC2 instance in AWS.
# More information about the aws_instance resource can be found here: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/instance
resource "aws_instance" "ec2" {
  ami = "ami-00f46ccd1cbfb363e"
  instance_type = "t2.micro"
  tags = {
    Name = var.serverName 
  }
}



module "EIP" {
  source = "../eip"
  instanceID = aws_instance.ec2.id
}


# Output the Elastic IP 
# This output displays the public IP address of the allocated Elastic IP.
# More information about outputs can be found here: https://www.terraform.io/language/values/outputs
output "EIP-private_ip" {
  value = module.EIP.EIP-private_ip
} 

output "EIP-public_ip" {
  value = module.EIP.EIP-public_ip
} 