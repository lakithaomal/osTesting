variable "instanceID" {
  description = "Instance ID to associate the Elastic IP with"
  type        = string
}

# Elastic IP Resource
# This resource allocates an Elastic IP and associates it with the EC2 instance.
# More information about the aws_eip resource can be found here: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/eip
resource "aws_eip" "elastic_ip" {
  instance = var.instanceID
}

# Output the Elastic IP 
# This output displays the public IP address of the allocated Elastic IP.
# More information about outputs can be found here: https://www.terraform.io/language/values/outputs
output "EIP-private_ip" {
  value = aws_eip.elastic_ip.private_ip
} 

output "EIP-public_ip" {
  value = aws_eip.elastic_ip.public_ip
} 