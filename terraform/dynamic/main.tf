
provider "aws" {
    region = "us-west-2"
}

resource "aws_instance" "ec2" {
  ami = "ami-00f46ccd1cbfb363e"
  instance_type = "t3.micro"
  security_groups = [ aws_security_group.webtraffic.name]
}


variable "ingressrules" {
  type = list(number)  
  default = [80,443]
}

variable "egressrules" {
  type = list(number)  
  default = [80,443,25,3306,53,8080]
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
  