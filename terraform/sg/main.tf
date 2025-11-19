
provider "aws" {
    region = "us-west-2"
}

resource "aws_instance" "ec2" {
  ami = "ami-00f46ccd1cbfb363e"
  instance_type = "t3.micro"
  security_groups = [ aws_security_group.webtraffic.name]
}

resource "aws_security_group" "webtraffic" {
  name        = "allow_web_traffic"
  description = "Allow inbound HTTP and HTTPS traffic"
  
  ingress {
    description = "HTTP from VPC"
    from_port   = 443
    to_port     = 443
    protocol    = "TCP"
    cidr_blocks = ["0.0.0.0/0"]   
  }
  egress {
    description = "HTTP from VPC"
    from_port   = 443
    to_port     = 443
    protocol    = "TCP"
    cidr_blocks = ["0.0.0.0/0"]   
  }
}
  