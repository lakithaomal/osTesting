
variable "ingressrules" {
  type = list(number)  
  default = [80,22,443]
}

variable "egressrules" {
  type = list(number)  
  default = [80,22,443]
}