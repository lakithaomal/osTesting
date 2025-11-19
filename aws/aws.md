# What is an IAM User in AWS?

## 🔐 Definition

An **IAM User (Identity and Access Management User)** is:

> **A long-term identity in AWS for a person or system that needs direct
> access to AWS using a username, password, and/or access keys.**

It can represent: - A **human** (developer, admin) - A **system**
(script, Terraform, Ansible, CI/CD)

------------------------------------------------------------------------

## 🧩 Key Characteristics

### ✔️ Long-term identity

Exists until deleted.

### ✔️ Has credentials

An IAM user may have: - AWS console **username/password** - **Access
keys** (Access Key ID + Secret) for CLI/API/Terraform

### ✔️ Has permissions

Permissions come from: - AWS-managed policies\
- Custom JSON policies\
- Group-based policies

------------------------------------------------------------------------

## 📌 Common Uses

IAM users are used for: - Developers logging into AWS console\
- Terraform using AWS credentials\
- Ansible using AWS modules\
- Scripts interacting with S3, EC2, etc.\
- CI/CD systems that need long-term access

------------------------------------------------------------------------

## ❌ What IAM Users Are *Not*

-   Not for short-lived credentials\
-   Not meant to be shared\
-   Not ideal for automation (prefer IAM **roles**)

------------------------------------------------------------------------

## ⭐ Best Practice

**Use IAM Roles wherever possible.\
Use IAM Users only when roles cannot be used.**

Better alternatives: - EC2 Instance Role\
- Lambda Execution Role\
- GitHub Actions OIDC Role\
- IAM Federation/SSO

------------------------------------------------------------------------

## 🆚 IAM User vs IAM Role

  Feature         IAM User                IAM Role
  --------------- ----------------------- --------------------------------
  Credentials     Permanent               Temporary (STS)
  Intended for    People or systems       AWS services / federated users
  Access Keys     Yes                     No
  Console Login   Yes (if password set)   No
  Best Practice   Use sparingly           Use frequently

------------------------------------------------------------------------

## 🪄 One-Sentence Summary

**An IAM User is a permanent AWS identity with long-term credentials
used by a person or system to access AWS services.**

------------------------------------------------------------------------

## Create IAM User

-   Attach Admin Policies --- **NOT recommended**\
-   Prefer assigning only the minimum permissions required\
-   Use groups and managed policies to organize access

------------------------------------------------------------------------

## Create Keys for the User

-   Keep access keys **secure**\
-   **Never** upload keys online or store them in GitHub\
-   Recommended ways to store/use keys:
    -   Environment variables\
    -   AWS CLI configuration (`aws configure`)\
    -   AWS Vault / SSM Parameter Store / Secrets Manager\

------------------------------------------------------------------------

## Using Multiple AWS Credentials (Named Profiles)

You can configure multiple AWS accounts or identities on the same machine
using **named profiles**.

### ✔️ Add Multiple Profiles to `~/.aws/credentials`

```
[default]
aws_access_key_id = YOUR_DEFAULT_KEY
aws_secret_access_key = YOUR_DEFAULT_SECRET

[sandbox]
aws_access_key_id = YOUR_SANDBOX_KEY
aws_secret_access_key = YOUR_SANDBOX_SECRET

[prod]
aws_access_key_id = YOUR_PROD_KEY
aws_secret_access_key = YOUR_PROD_SECRET
```

### ✔️ Configure Using AWS CLI

Run:

```
aws configure --profile sandbox
aws configure --profile prod
aws configure --profile personal
```

### ✔️ Use a Profile

```
aws s3 ls --profile sandbox
aws ec2 describe-instances --profile prod
```

### ✔️ Use With Terraform

```
provider "aws" {
  region  = "us-east-1"
  profile = "sandbox"
}
```

### ✔️ Environment Variable Option

```
export AWS_PROFILE=sandbox
```

------------------------------------------------------------------------

## Understanding CIDR Blocks in AWS

A **CIDR block** (Classless Inter-Domain Routing block) defines an IP address range.
AWS uses CIDR blocks for VPCs, subnets, security groups, and routing.

### 🔹 What a CIDR Block Looks Like
```
10.0.0.0/16
```

This has two parts:
- **10.0.0.0** → starting IP  
- **/16** → number of **network bits** (fixed)

IPv4 addresses contain **32 bits**, so the remaining bits are **host bits**.

---

### 🔹 How CIDR Is Calculated

**Formula:**  
```
Number of IPs = 2^(32 – prefix)
```

Examples:
- `/16` → 32–16 = 16 host bits → 2^16 = **65,536 IPs**
- `/24` → 32–24 = 8 host bits → 2^8 = **256 IPs**
- `/20` → 32–20 = 12 host bits → 2^12 = **4,096 IPs**
- `/28` → 32–28 = 4 host bits → 2^4 = **16 IPs**

AWS reserves **5 IPs** in every subnet, so usable IPs = total − 5.

---

### 🔹 Visual Explanation (Bit-Based)

IPv4 example:
```
10.0.0.0 = 00001010.00000000.00000000.00000000
```

A CIDR like `/16` locks the first 16 bits:
```
Network bits: 00001010.00000000 | Host bits: XXXXXXXXXXXXXXXX
```

Host bits can vary, producing IP addresses.

---

### 🔹 Why AWS Reserves 5 IPs

Every subnet always reserves:
1. Network address  
2. VPC router  
3. AWS future use  
4. Broadcast address  
5. One additional reserved address  

So for `/24`:
```
256 total − 5 reserved = 251 usable
```

---

### 🔹 Common CIDR Blocks in AWS

| CIDR | Total IPs | Usable in AWS | Usage |
|------|-----------|---------------|-------|
| /16 | 65,536 | 65,531 | VPC |
| /20 | 4,096 | 4,091 | Medium subnet |
| /24 | 256 | 251 | Small subnet |
| /28 | 16 | 11 | Very small subnet |

---

### 🔹 Example Range Calculation

Subnet:
```
10.0.1.0/24
```

- Total IPs: 256  
- Usable: 10.0.1.4 → 10.0.1.254  
- Reserved:  
  - 10.0.1.0 (network)  
  - 10.0.1.1 (router)  
  - 10.0.1.2–10.0.1.3 (reserved)  
  - 10.0.1.255 (broadcast)

---

### ⭐ One-Sentence Summary

**CIDR divides a 32‑bit IPv4 address into fixed network bits and variable host bits; total IPs = 2^(host bits).**

