
variable "server_name" {
  type = list(string)
}       


resource "aws_instance" "ec2Instance" {
  ami = "ami-00f46ccd1cbfb363e"
  instance_type = "t3.micro"
  count = length(
    var.server_name 
  )

  tags = {
    Name = var.server_name[count.index]
  }
}



output "private_ips" {
  value = aws_instance.ec2Instance[*].private_ip
}