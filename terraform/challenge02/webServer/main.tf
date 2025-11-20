
#  Provider Configuration 
# This can be used to configure the AWS provider, AZURe provider, GCP provider, and so on.
# More information about provider configuration can be found here:
# https://registry.terraform.io/providers/hashicorp/aws/latest/docs#configuration

provider "aws" {
    region = "us-west-2"
    profile = var.aws_profile
}

# EC2 Instance Resource
# This resource creates an EC2 instance in AWS.
# More information about the aws_instance resource can be found here: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/instance

resource "aws_instance" "ec2" {
  ami = "ami-00f46ccd1cbfb363e"
  instance_type = "t2.micro"
  security_groups = [aws_security_group.webtraffic.name]
  tags = {
    Name = "Web Server"
  }
  user_data = <<-EOF
    #!/bin/bash
    apt-get update -y
    apt-get install -y apache2
    systemctl start apache2
    systemctl enable apache2
    echo "<h1>Hello from Terraform (Ubuntu)</h1>" > /var/www/html/index.html
  EOF


}



resource "aws_security_group" "webtraffic" {
  name        = "allow_web_traffic"
  description = "Allow inbound HTTP and HTTPS traffic"
  
  dynamic "ingress" {
    iterator = port
    for_each = var.ingressrules
    content {
      from_port   = port.value
      to_port     = port.value
      protocol    = "TCP"
      cidr_blocks = ["0.0.0.0/0"]   
    }
  }
  dynamic "egress" {
    iterator = port
    for_each = var.egressrules
    content {
      from_port   = port.value
      to_port     = port.value
      protocol    = "TCP"
    cidr_blocks = ["0.0.0.0/0"]   
  }
}
}
  



# Elastic IP Resource
# This resource allocates an Elastic IP and associates it with the EC2 instance.
# More information about the aws_eip resource can be found here: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/eip
resource "aws_eip" "elastic_ip" {
  instance = aws_instance.ec2.id
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