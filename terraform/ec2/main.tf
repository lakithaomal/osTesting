
provider "aws" {
    region = "us-west-2"
}

resource "aws_instance" "ec2" {
  ami = "ami-00f46ccd1cbfb363e"
  instance_type = "t3.micro"
}