

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
  
# Need to specify as an output to be accessible from other modules
output "sg_name" {
    value = aws_security_group.webtraffic.name
}
