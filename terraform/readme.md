## Terraform Commands

Terraform uses a simple workflow: **initialize → plan → apply → destroy**.  
These commands form the core lifecycle of managing infrastructure as code (IaC).

---

### `terraform init`
Initializes a Terraform working directory.

This command:
- Downloads and installs the required providers (AWS, Azure, GCP, etc.)
- Sets up the `.terraform` directory
- Prepares the backend (if configured)

You must run this **once**, before any plan or apply.

Example:
```
terraform init
```

---

### `terraform plan`
Creates an execution plan showing what actions Terraform will take.

This command:
- Compares your `.tf` configuration with the real infrastructure
- Shows additions, updates, and deletions
- Does **not** make changes—only displays them

Example:
```
terraform plan
```

Use this to verify the changes before applying.

---

### `terraform apply`
Applies the changes required to reach the desired state.

This command:
- Executes the actions shown in the plan
- Creates, updates, or deletes resources on the provider
- Prompts for approval unless `-auto-approve` is used

Example:
```
terraform apply
```

---


### `terraform destroy`
Destroys all resources managed by Terraform in the current workspace.

This command:
- Reads the state file
- Determines what Terraform created
- Removes everything safely and in order

Use this for cleanup in sandbox/test environments.

Example:
```
terraform destroy
```

---


## Checking Your Created VPC in AWS

After running `terraform apply`, Terraform will output something like:

```
aws_vpc.my_first_vpc: Creation complete after 3s [id=vpc-xxxxxxxxxxxxxxxxx]
```

To verify that the VPC was successfully created, you can check it in multiple ways:

### ✔️ 1. Check in AWS Console (GUI)
1. Go to **AWS Console**
2. Navigate to **VPC → Your VPCs**
3. Search for the VPC ID Terraform printed, for example:

```
vpc-0101082101f52479f
```

You should see:
- The VPC ID  
- CIDR block (e.g., 10.0.0.0/16)  
- State = *available*

---

### ✔️ 2. Check Using AWS CLI
Run:

```bash
aws ec2 describe-vpcs --vpc-ids <your_vpc_id> --region us-west-2
```

Example:

```bash
aws ec2 describe-vpcs --vpc-ids vpc-0101082101f52479f --region us-west-2
```

If the VPC exists, you will see JSON output with VPC details.

---

### ✔️ 3. Check Using Terraform State
Terraform tracks resources it creates in a state file.

List resources tracked by Terraform:

```bash
terraform state list
```

Inspect details of your VPC:

```bash
terraform state show aws_vpc.my_first_vpc
```

---

### ✔️ 4. (Optional) Add Terraform Output for Easy Access
Add this to your Terraform file:

```terraform
output "vpc_id" {
  value = aws_vpc.my_first_vpc.id
}
```

Then run:

```bash
terraform output
```

You will see:

```
vpc_id = "vpc-xxxxxxxxxxxxxxxxx"
```

---


---

## Understanding `main.tf`

```
#  Provider Configuration 
# This can be used to configure the AWS provider, AZURe provider, GCP provider, and so on.
# More information about provider configuration can be found here:
# https://registry.terraform.io/providers/hashicorp/aws/latest/docs#configuration

provider "aws" {
    region = "us-west-2"
}

# Resource Definition
# This block defines an AWS VPC resource with a specified CIDR block.
# More information about AWS VPC resource can be found here:
# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc

# Create an AWS VPC with a CIDR block of 10.0.0.0/16    
#  my_first_vpc is the name given to this resource instance.
resource "aws_vpc" "my_first_vpc" {
    cidr_block = "10.0.0.0/16"
}
```

The `main.tf` file is the primary Terraform configuration file. It defines **which cloud provider Terraform should use** and **what resources should be created**.

Below is a breakdown of the example:

---

### ✔️ Provider Configuration

```terraform
provider "aws" {
    region = "us-west-2"
}
```

This block tells Terraform:

- Use the **AWS provider**
- Deploy resources into the **us-west-2** region (Oregon)

Terraform can work with many providers:
- AWS  
- Azure  
- Google Cloud  
- Kubernetes  
- GitHub  
- Cloudflare  
and more.

The provider block initializes AWS-specific functionality so Terraform knows how to create AWS resources.

---

### ✔️ Resource Definition: AWS VPC

```terraform
resource "aws_vpc" "my_first_vpc" {
    cidr_block = "10.0.0.0/16"
}
```

This block defines an AWS **VPC (Virtual Private Cloud)** resource.

- `aws_vpc` → the AWS VPC resource type  
- `"my_first_vpc"` → the name of this resource instance inside Terraform  
- `cidr_block` → the IP address range for the VPC

`10.0.0.0/16` means:
- The VPC will have **65,536 IP addresses**
- Subnets created later must fall inside this range

Terraform will create this VPC when you run:

```
terraform apply
```

Terraform will also track the resource in `terraform.tfstate`, allowing it to manage updates and deletions over time.

---

### ✔️ Summary


- **Provider block** = Which cloud platform Terraform talks to  
- **Resource block** = What infrastructure Terraform creates  
- `main.tf` = Central file that defines your infrastructure as code

---

## Understanding the Terraform State File (`terraform.tfstate`)

Terraform uses a **state file** to keep track of all infrastructure it manages.  
This file is essential because it acts as the *source of truth* for Terraform.

### ✔️ What is the Terraform State File?

When you run `terraform apply`, Terraform creates (or updates) a file called:

```
terraform.tfstate
```

This file contains:
- The resources Terraform created  
- Their IDs (e.g., VPC ID, subnet IDs, etc.)  
- Metadata and attributes returned by AWS  
- Dependency relationships  

Terraform uses this file to:
- Compare real infrastructure vs your `.tf` files  
- Determine what needs to be created, changed, or deleted  
- Track which resources *it* manages  

---

### ✔️ Why is the State File Important?

Without the state file:
- Terraform wouldn’t know what it already created  
- It would re-create resources each time  
- It wouldn’t be able to update or destroy infrastructure safely  

Example:  
If Terraform created your VPC, its ID will be stored in the state file.  
Next time you run `terraform plan`, Terraform reads the state and knows:

> “This VPC already exists — don’t recreate it.”

---

### ✔️ Where is the State File Stored?

By default:

```
terraform.tfstate
```

in the same directory where you run Terraform.

This is fine for:
- Local experiments  
- Sandbox development  
- Testing  

But **NOT** safe for production because:
- It contains sensitive data (like ARNs and attributes)
- It can be lost if your laptop crashes
- It does not support team collaboration

---

### ✔️ Remote State (Best Practice)

For real environments, store the state file in a **remote backend**, such as:

- AWS S3 (most common)
- Terraform Cloud
- GitLab backend
- Consul
- Azure Blob Storage
- Google Cloud Storage

Example (S3 backend):

```terraform
terraform {
  backend "s3" {
    bucket         = "my-terraform-state-bucket"
    key            = "networking/terraform.tfstate"
    region         = "us-west-2"
    dynamodb_table = "terraform-locks"
  }
}
```

This gives you:
- Centralized shared state  
- State locking (prevents two people running apply at the same time)  
- Versioning  
- Reliability  

---

### ✔️ Inspecting the State

To see what Terraform is tracking:

```
terraform state list
```

To inspect a specific resource:

```
terraform state show aws_vpc.my_first_vpc
```

To remove a resource from state (advanced):

```
terraform state rm <resource>
```

---

### ✔️ Key Takeaways

- Terraform needs the state file to understand what exists.
- Never delete the `terraform.tfstate` file unless you want Terraform to forget everything it created.
- Use **remote state** for production or team environments.
- The state file maps real cloud resources to your Terraform configuration.


# Terraform Variables Guide

This document explains **all Terraform variables used in your provided configuration**, including strings, numbers, booleans, lists, maps, tuples, and objects — with clear explanations and examples.

---

# 🔹 1. String Variable

A **string** represents plain text.

```terraform
variable "vpcname" {
  type    = string
  default = "myvpc"
}
```

### Usage
```terraform
tags = {
  Name = var.vpcname
}
```

---

# 🔹 2. Number Variable

A **number** can be an integer or float.

```terraform
variable "sshport" {
  type    = number
  default = 22
}
```

### Usage
Used for:
- Ports
- Counts
- Resource sizing

---

# 🔹 3. Boolean Variable

A boolean represents **true** or **false**.

```terraform
variable "enabled" {
  default = true
}
```

### Usage
```terraform
enable_dns_support = var.enabled
```

---

# 🔹 4. List Variable

A **list** is an ordered collection of values.

```terraform
variable "mylist" {
  type    = list(string)
  default = ["Value1", "Value2"]
}
```

### Usage
```terraform
element(var.mylist, 0)
```

---

# 🔹 5. Map Variable

A **map** is a key/value dictionary.

```terraform
variable "mymap" {
  type = map
  default = {
    Key1 = "Value1"
    Key2 = "Value2"
  }
}
```

### Usage
```terraform
var.mymap["Key1"]
```

---

# 🔹 6. Input Variable (No Default)

This variable **must be provided** at runtime.

```terraform
variable "inputname" {
  type        = string
  description = "Set the name of the VPC"
}
```

### Usage
You must provide this in:
- `terraform.tfvars`
- CLI
- or var-file

Example:

```terraform
inputname = "production-vpc"
```

---

# 🔹 7. Tuple Variable

A tuple contains **ordered values of mixed types**.

```terraform
variable "mytuple" {
  type    = tuple([string, number, string])
  default = ["cat", 1, "dog"]
}
```

### Usage
```terraform
var.mytuple[0] # "cat"
var.mytuple[1] # 1
```

---

# 🔹 8. Object Variable

An object is a **structured set of attributes** with defined types.

```terraform
variable "myobject" {
  type = object({ 
      name = string, 
      port = list(number) 
  })
  default = {
    name = "TJ"
    port = [22, 25, 80]
  }
}
```

### Usage
```terraform
var.myobject.name
var.myobject.port[0]
```

---

# AWS Resource Definition Using Variables

Your VPC resource uses the variable `inputname` to dynamically set the VPC name.

```terraform
resource "aws_vpc" "myvpc" {
  cidr_block = "10.0.0.0/16"

  tags = {
    Name = var.inputname
  }
}
```

---

# Output Example

Outputs allow Terraform to show values after apply.

```terraform
output "vpcid" {
  value = aws_vpc.myvpc.id
}
```

Usage:

```bash
terraform output
```

---

## Summary of Variable Types Used

| Variable      | Type            | Example Use |
|---------------|-----------------|-------------|
| `vpcname`     | string          | Naming resources |
| `sshport`     | number          | Port configuration |
| `enabled`     | boolean         | Feature toggles |
| `mylist`      | list(string)    | Multiple values |
| `mymap`       | map             | Lookup tables |
| `inputname`   | string (input)  | User-provided names |
| `mytuple`     | tuple           | Mixed-type sequences |
| `myobject`    | object          | Structured config |

---

## Terraform Commands

Terraform uses a simple workflow: **initialize → plan → apply → destroy**.  
These commands form the core lifecycle of managing infrastructure as code (IaC).

---

### `terraform init`
Initializes a Terraform working directory.

This command:
- Downloads and installs the required providers (AWS, Azure, GCP, etc.)
- Sets up the `.terraform` directory
- Prepares the backend (if configured)

You must run this **once**, before any plan or apply.

Example:
```
terraform init
```

---

### `terraform plan`
Creates an execution plan showing what actions Terraform will take.

This command:
- Compares your `.tf` configuration with the real infrastructure
- Shows additions, updates, and deletions
- Does **not** make changes—only displays them

Example:
```
terraform plan
```

Use this to verify the changes before applying.

---

### `terraform apply`
Applies the changes required to reach the desired state.

This command:
- Executes the actions shown in the plan
- Creates, updates, or deletes resources on the provider
- Prompts for approval unless `-auto-approve` is used

Example:
```
terraform apply
```

---


### `terraform destroy`
Destroys all resources managed by Terraform in the current workspace.

This command:
- Reads the state file
- Determines what Terraform created
- Removes everything safely and in order

Use this for cleanup in sandbox/test environments.

Example:
```
terraform destroy
```

---


## Checking Your Created VPC in AWS

After running `terraform apply`, Terraform will output something like:

```
aws_vpc.my_first_vpc: Creation complete after 3s [id=vpc-xxxxxxxxxxxxxxxxx]
```

To verify that the VPC was successfully created, you can check it in multiple ways:

### ✔️ 1. Check in AWS Console (GUI)
1. Go to **AWS Console**
2. Navigate to **VPC → Your VPCs**
3. Search for the VPC ID Terraform printed, for example:

```
vpc-0101082101f52479f
```

You should see:
- The VPC ID  
- CIDR block (e.g., 10.0.0.0/16)  
- State = *available*

---

### ✔️ 2. Check Using AWS CLI
Run:

```bash
aws ec2 describe-vpcs --vpc-ids <your_vpc_id> --region us-west-2
```

Example:

```bash
aws ec2 describe-vpcs --vpc-ids vpc-0101082101f52479f --region us-west-2
```

If the VPC exists, you will see JSON output with VPC details.

---

### ✔️ 3. Check Using Terraform State
Terraform tracks resources it creates in a state file.

List resources tracked by Terraform:

```bash
terraform state list
```

Inspect details of your VPC:

```bash
terraform state show aws_vpc.my_first_vpc
```

---

### ✔️ 4. (Optional) Add Terraform Output for Easy Access
Add this to your Terraform file:

```terraform
output "vpc_id" {
  value = aws_vpc.my_first_vpc.id
}
```

Then run:

```bash
terraform output
```

You will see:

```
vpc_id = "vpc-xxxxxxxxxxxxxxxxx"
```

---


---

## Understanding `main.tf`

```
#  Provider Configuration 
# This can be used to configure the AWS provider, AZURe provider, GCP provider, and so on.
# More information about provider configuration can be found here:
# https://registry.terraform.io/providers/hashicorp/aws/latest/docs#configuration

provider "aws" {
    region = "us-west-2"
}

# Resource Definition
# This block defines an AWS VPC resource with a specified CIDR block.
# More information about AWS VPC resource can be found here:
# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc

# Create an AWS VPC with a CIDR block of 10.0.0.0/16    
#  my_first_vpc is the name given to this resource instance.
resource "aws_vpc" "my_first_vpc" {
    cidr_block = "10.0.0.0/16"
}
```

The `main.tf` file is the primary Terraform configuration file. It defines **which cloud provider Terraform should use** and **what resources should be created**.

Below is a breakdown of the example:

---

### ✔️ Provider Configuration

```terraform
provider "aws" {
    region = "us-west-2"
}
```

This block tells Terraform:

- Use the **AWS provider**
- Deploy resources into the **us-west-2** region (Oregon)

Terraform can work with many providers:
- AWS  
- Azure  
- Google Cloud  
- Kubernetes  
- GitHub  
- Cloudflare  
and more.

The provider block initializes AWS-specific functionality so Terraform knows how to create AWS resources.

---

### ✔️ Resource Definition: AWS VPC

```terraform
resource "aws_vpc" "my_first_vpc" {
    cidr_block = "10.0.0.0/16"
}
```

This block defines an AWS **VPC (Virtual Private Cloud)** resource.

- `aws_vpc` → the AWS VPC resource type  
- `"my_first_vpc"` → the name of this resource instance inside Terraform  
- `cidr_block` → the IP address range for the VPC

`10.0.0.0/16` means:
- The VPC will have **65,536 IP addresses**
- Subnets created later must fall inside this range

Terraform will create this VPC when you run:

```
terraform apply
```

Terraform will also track the resource in `terraform.tfstate`, allowing it to manage updates and deletions over time.

---

### ✔️ Summary


- **Provider block** = Which cloud platform Terraform talks to  
- **Resource block** = What infrastructure Terraform creates  
- `main.tf` = Central file that defines your infrastructure as code

---

## Understanding the Terraform State File (`terraform.tfstate`)

Terraform uses a **state file** to keep track of all infrastructure it manages.  
This file is essential because it acts as the *source of truth* for Terraform.

### ✔️ What is the Terraform State File?

When you run `terraform apply`, Terraform creates (or updates) a file called:

```
terraform.tfstate
```

This file contains:
- The resources Terraform created  
- Their IDs (e.g., VPC ID, subnet IDs, etc.)  
- Metadata and attributes returned by AWS  
- Dependency relationships  

Terraform uses this file to:
- Compare real infrastructure vs your `.tf` files  
- Determine what needs to be created, changed, or deleted  
- Track which resources *it* manages  

---

### ✔️ Why is the State File Important?

Without the state file:
- Terraform wouldn’t know what it already created  
- It would re-create resources each time  
- It wouldn’t be able to update or destroy infrastructure safely  

Example:  
If Terraform created your VPC, its ID will be stored in the state file.  
Next time you run `terraform plan`, Terraform reads the state and knows:

> “This VPC already exists — don’t recreate it.”

---

### ✔️ Where is the State File Stored?

By default:

```
terraform.tfstate
```

in the same directory where you run Terraform.

This is fine for:
- Local experiments  
- Sandbox development  
- Testing  

But **NOT** safe for production because:
- It contains sensitive data (like ARNs and attributes)
- It can be lost if your laptop crashes
- It does not support team collaboration

---

### ✔️ Remote State (Best Practice)

For real environments, store the state file in a **remote backend**, such as:

- AWS S3 (most common)
- Terraform Cloud
- GitLab backend
- Consul
- Azure Blob Storage
- Google Cloud Storage

Example (S3 backend):

```terraform
terraform {
  backend "s3" {
    bucket         = "my-terraform-state-bucket"
    key            = "networking/terraform.tfstate"
    region         = "us-west-2"
    dynamodb_table = "terraform-locks"
  }
}
```

This gives you:
- Centralized shared state  
- State locking (prevents two people running apply at the same time)  
- Versioning  
- Reliability  

---

### ✔️ Inspecting the State

To see what Terraform is tracking:

```
terraform state list
```

To inspect a specific resource:

```
terraform state show aws_vpc.my_first_vpc
```

To remove a resource from state (advanced):

```
terraform state rm <resource>
```

---

### ✔️ Key Takeaways

- Terraform needs the state file to understand what exists.
- Never delete the `terraform.tfstate` file unless you want Terraform to forget everything it created.
- Use **remote state** for production or team environments.
- The state file maps real cloud resources to your Terraform configuration.


# Terraform Variables Guide

This document explains **all Terraform variables used in your provided configuration**, including strings, numbers, booleans, lists, maps, tuples, and objects — with clear explanations and examples.

---

# 🔹 1. String Variable

A **string** represents plain text.

```terraform
variable "vpcname" {
  type    = string
  default = "myvpc"
}
```

### Usage
```terraform
tags = {
  Name = var.vpcname
}
```

---

# 🔹 2. Number Variable

A **number** can be an integer or float.

```terraform
variable "sshport" {
  type    = number
  default = 22
}
```

### Usage
Used for:
- Ports
- Counts
- Resource sizing

---

# 🔹 3. Boolean Variable

A boolean represents **true** or **false**.

```terraform
variable "enabled" {
  default = true
}
```

### Usage
```terraform
enable_dns_support = var.enabled
```

---

# 🔹 4. List Variable

A **list** is an ordered collection of values.

```terraform
variable "mylist" {
  type    = list(string)
  default = ["Value1", "Value2"]
}
```

### Usage
```terraform
element(var.mylist, 0)
```

---

# 🔹 5. Map Variable

A **map** is a key/value dictionary.

```terraform
variable "mymap" {
  type = map
  default = {
    Key1 = "Value1"
    Key2 = "Value2"
  }
}
```

### Usage
```terraform
var.mymap["Key1"]
```

---

# 🔹 6. Input Variable (No Default)

This variable **must be provided** at runtime.

```terraform
variable "inputname" {
  type        = string
  description = "Set the name of the VPC"
}
```

### Usage
You must provide this in:
- `terraform.tfvars`
- CLI
- or var-file

Example:

```terraform
inputname = "production-vpc"
```

---

# 🔹 7. Tuple Variable

A tuple contains **ordered values of mixed types**.

```terraform
variable "mytuple" {
  type    = tuple([string, number, string])
  default = ["cat", 1, "dog"]
}
```

### Usage
```terraform
var.mytuple[0] # "cat"
var.mytuple[1] # 1
```

---

# 🔹 8. Object Variable

An object is a **structured set of attributes** with defined types.

```terraform
variable "myobject" {
  type = object({ 
      name = string, 
      port = list(number) 
  })
  default = {
    name = "TJ"
    port = [22, 25, 80]
  }
}
```

### Usage
```terraform
var.myobject.name
var.myobject.port[0]
```

---

# AWS Resource Definition Using Variables

Your VPC resource uses the variable `inputname` to dynamically set the VPC name.

```terraform
resource "aws_vpc" "myvpc" {
  cidr_block = "10.0.0.0/16"

  tags = {
    Name = var.inputname
  }
}
```

---

# Output Example

Outputs allow Terraform to show values after apply.

```terraform
output "vpcid" {
  value = aws_vpc.myvpc.id
}
```

Usage:

```bash
terraform output
```

---

## Summary of Variable Types Used

| Variable      | Type            | Example Use |
|---------------|-----------------|-------------|
| `vpcname`     | string          | Naming resources |
| `sshport`     | number          | Port configuration |
| `enabled`     | boolean         | Feature toggles |
| `mylist`      | list(string)    | Multiple values |
| `mymap`       | map             | Lookup tables |
| `inputname`   | string (input)  | User-provided names |
| `mytuple`     | tuple           | Mixed-type sequences |
| `myobject`    | object          | Structured config |

---

# Terraform Examples for `count`, `for_each`, and Conditional Resources

### 1. Count Example
This only works on legacy systems. On current versions use For Each. 
**⭐ Provided Example**
```
provider "aws" {
    region = "eu-west-2"
}
module "ec2" {
    source = "./ec2"
    count  = 3
}
```

---

### 2. For_Each Example

**⭐ Provided Example**
```
provider "aws" {
    region = "eu-west-2"
}
module "ec2" {
    source   = "./ec2"
    for_each = toset(["dev", "test", "prod"])
}
```

---

### 3. Conditional Count (“Switch Feature”)

**⭐ Provided Example**
```
provider "aws" {
    region = "eu-west-2"
}
variable "environment" {
    type = string
}
resource "aws_instance" "ec2" {
    count = var.environment == "prod" ? 5 : 1 
    # other resource config
}
```

`count = var.environment == "prod" ? 5 : 1 ` This is a tertianary operator. 

In order to run this you need to use one of these input files. 

**⭐ prod.tfvars**
```hcl
number_of_servers = 50
environment       = "prod"
```

**⭐ test.tfvars**
```hcl
number_of_servers = 2
environment       = "test"
```
` terraform plan -var-file =  prod.tfvars   ` for example. 

---
