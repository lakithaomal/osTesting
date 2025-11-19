# AWS EC2 with Terraform  

[Documentation](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/instance.html)
This guide explains how to create EC2 instances using Terraform.  
Each section includes **clean examples**, **clear explanations**, and **readable code blocks**.

---

# 📘 1. EC2 Basics — Creating an Instance

To launch an EC2 instance, you must define:

- The **AWS provider**  
- The **AMI ID** (Amazon Machine Image)  
- The **instance type** (e.g., t3.micro)

### ✅ Example: Minimal EC2 Instance

```hcl
provider "aws" {
  region = "us-west-2"
}

resource "aws_instance" "ec2" {
  ami           = "ami-00f46ccd1cbfb363e"
  instance_type = "t3.micro"
}
```

### 📝 Explanation

- `provider "aws"`  
  Tells Terraform which cloud provider and region to use.

- `resource "aws_instance" "ec2"`  
  Creates an EC2 instance named `ec2`.

- `ami = "ami-00f46ccd1cbfb363e"`  
  Defines the OS image. This AMI might be Amazon Linux or Ubuntu depending on its ID.

- `instance_type = "t3.micro"`  
  Defines the hardware (CPU/RAM).

---

# 📗 2. Attaching an Elastic IP (EIP)

An **Elastic IP** is a public, static IPv4 address that stays the same even if you stop and start the instance.

### ✅ Example: EC2 + Elastic IP

```hcl
provider "aws" {
  region = "us-west-2"
}

resource "aws_instance" "ec2" {
  ami           = "ami-00f46ccd1cbfb363e"
  instance_type = "t3.micro"
}

resource "aws_eip" "elastic_ip" {
  instance = aws_instance.ec2.id
}

output "EIP" {
  value = aws_eip.elastic_ip.public_ip
}
```

### 📝 Explanation

- `aws_eip.elastic_ip`  
  Allocates a static IP and associates it with the EC2 instance.

- `output "EIP"`  
  Prints the public IP after running `terraform apply`.

---

# 📕 3. Security Groups (Allowing Traffic)

Security Groups act as **virtual firewalls**.

### Example: Allow HTTPS traffic (port 443)

```hcl
provider "aws" {
  region = "us-west-2"
}

resource "aws_instance" "ec2" {
  ami             = "ami-00f46ccd1cbfb363e"
  instance_type   = "t3.micro"
  security_groups = [aws_security_group.webtraffic.name]
}

resource "aws_security_group" "webtraffic" {
  name        = "allow_web_traffic"
  description = "Allow inbound HTTP and HTTPS traffic"

  ingress {
    description = "Allow HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "TCP"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Allow outbound HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "TCP"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
```

### 📝 Explanation

- `ingress`  
  Incoming traffic rules.  
  This one allows HTTPS (443) from any IP.

- `egress`  
  Outgoing traffic rules.

- `security_groups` in `aws_instance`  
  Associates the EC2 instance with the security group.

---

# 📙 4. Dynamic Security Group Rules (Advanced)

Dynamic blocks help when you want to avoid repeating code.

Here, we allow inbound/outbound rules using **lists of ports**.

### Variables

```hcl
variable "ingressrules" {
  type    = list(number)
  default = [80, 443]
}

variable "egressrules" {
  type    = list(number)
  default = [80, 443, 25, 3306, 53, 8080]
}
```

---

# Security Group with Dynamic Rules

```hcl
resource "aws_security_group" "webtraffic" {
  name        = "allow_dynamic_traffic"
  description = "Allow dynamic inbound and outbound traffic"

  # Ingress rules generated dynamically
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

  # Egress rules generated dynamically
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
```

### 📝 Explanation

- `dynamic "ingress"`  
  Replaces many repeated ingress blocks with a loop.

- `iterator = port`  
  Name of the loop variable.

- `port.value`  
  Each element from the provided list.

This produces **one ingress rule per port** in the variable list.

---

# ✔️ Summary

| Feature | Description |
|--------|-------------|
| EC2 | Actual virtual server |
| Elastic IP | Permanent public IP |
| Security Group | Firewall for EC2 |
| Dynamic Block | Generates repeated blocks programmatically |
