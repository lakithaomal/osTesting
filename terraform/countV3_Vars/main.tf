
provider "aws" {
    region = "us-west-2"
    profile = var.aws_profile
}

resource "aws_instance" "ec2Instance" {
  ami = "ami-00f46ccd1cbfb363e"
  instance_type = "t3.micro"
  count = var.number_of_instances
}
