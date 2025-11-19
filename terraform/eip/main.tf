
provider "aws" {
    region = "us-west-2"
}

resource "aws_instance" "ec2" {
  ami = "ami-00f46ccd1cbfb363e"
  instance_type = "t3.micro"
}

 
resource "aws_eip" "elastic_ip" {
  instance = aws_instance.ec2.id
}

output "EIP" {
  value = aws_eip.elastic_ip.public_ip
} 