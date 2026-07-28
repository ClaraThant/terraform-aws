# VPC
# -----------------------------------------------
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16" # IP address range
  enable_dns_support   = true #use AWS DNS to resolve domain name
  enable_dns_hostnames = true #give hostnames to instances

  tags = {
    Name = "main-vpc"
  }
}

# SUBNETS
# ------------------------------------------------------------

# Public Subnet

resource "aws_subnet" "public_subnet" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24" #gives 256 IPs (251 usable, AWS reserves 5)
  availability_zone       = "us-east-1a"
  map_public_ip_on_launch = true #launched instances will get IP automatically, so that reachable by internet

  tags = {
    Name = "Public-subnet"
  }
}
/*
AWS reserves 5:
10.0.1.0 — network address
10.0.1.1 — AWS router
10.0.1.2 — AWS DNS
10.0.1.3 — reserved for future use
10.0.1.255 — broadcast address
*/


# Private Subnet
# 10.0.2.0/24 gives 256 IPs (251 usable, AWS reserves 5)
resource "aws_subnet" "private_subnet" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "us-east-1a"

  tags = {
    Name = "Private-subnet"
  }
}


# INTERNET GATEWAY (for the public subnet)
# =============================================
resource "aws_internet_gateway" "internet_gw" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "main-internet-gw"
  }
}

# Route table for public subnet
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  
  #rule
  route {
    cidr_block = "0.0.0.0/0" #all traffic, any IPs
    gateway_id = aws_internet_gateway.internet_gw.id
  }

  tags = {
    Name = "public-route"
  }
}

# Attach route table with public subnet
resource "aws_route_table_association" "public_association" {
  subnet_id      = aws_subnet.public_subnet.id
  route_table_id = aws_route_table.public.id
}


# EC2 INSTANCE (in the Public Subnet)
# =============================================

#auto getting amazon machine image instead of hard-coding
#Amazon Linux AMI
data "aws_ami" "my_ami_linux" {
  most_recent = true
  owners      = ["amazon"] #only amazon's

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# SSH KEY PAIR
# =============================================
# Uploads your local public key to AWS so EC2 instances can use it for SSH authentication
# The private key stays on your machine (~/.ssh/my-ec2-key), never uploaded
resource "aws_key_pair" "my_key" {
  key_name   = "my-ec2-key"
  public_key = file("~/.ssh/my-ec2-key.pub") #reads the public key file from your local machine
}


resource "aws_instance" "my_instance" {

  #***referencing a data source which is Linux AMI
  ami               = data.aws_ami.my_ami_linux.id 

  instance_type     = "t3.micro" #free server size ( 1vCPU, 1 GB RAm)
  subnet_id         = aws_subnet.public_subnet.id  #moved to public subnet so we can SSH in directly
  availability_zone = "us-east-1a"

  #attaching our custom security group instead of using the default VPC one
  vpc_security_group_ids = [aws_security_group.ec2_sg.id]

  #SSH key pair for authentication (public key gets uploaded to the instance)
  key_name = aws_key_pair.my_key.key_name

  tags = {
    Name = "my-ec2-instance"
  }
}


# EBS VOLUME (8 GB, attached to the EC2 instance)
# ------------------------------------------------------
resource "aws_ebs_volume" "my_volume" {
  availability_zone = "us-east-1a" # same AZ as EC2 that is gonna be attached
  size              = 8     #8GB
  type              = "gp2" #SSD

  tags = {
    Name = "my-ebs-volume"
  }
}

#attaching to EC2 instance
resource "aws_volume_attachment" "ebs_attach" {
  device_name = "/dev/xvdf"   #mount point on Linux , D:drive , default is xvda which is C:Drive
  volume_id   = aws_ebs_volume.my_volume.id
  instance_id = aws_instance.my_instance.id
}


# S3 BUCKET
# ----------------------------------------------------------

resource "aws_s3_bucket" "my_bucket" {
  #setting actual bucket id in AWS , it has to be globally uniuqe, so attach random numbers
  bucket = "my-private-bucket-${random_id.bucket_suffix.hex}"

  tags = {
    Name = "my-s3-bucket"
  }
}

# Random suffix to make the S3 bucket name globally unique
resource "random_id" "bucket_suffix" {
  byte_length = 4
}

#for access control list
# Block all public access
resource "aws_s3_bucket_public_access_block" "my_bucket_block" {
  bucket = aws_s3_bucket.my_bucket.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "my_bucket_ownership" {
  bucket = aws_s3_bucket.my_bucket.id

  rule {
    object_ownership = "BucketOwnerPreferred"
  }
}


resource "aws_s3_bucket_acl" "my_bucket_acl" {
  # New buckets default to BucketOwnerEnforced, which disables ACLs entirely.
  # The ownership controls above flip that to BucketOwnerPreferred, so ACLs must
  # be re-enabled before this resource can set one — otherwise AWS returns
  # AccessControlListNotSupported. Terraform can't infer this from a reference.
  depends_on = [aws_s3_bucket_ownership_controls.my_bucket_ownership]

  bucket = aws_s3_bucket.my_bucket.id
  acl    = "private"
}


# =============================================
# SECURITY GROUP (instance-level firewall for EC2)
# =============================================
/*
Security Groups are STATEFUL:
  - if you allow inbound traffic, the response is automatically allowed out
  - no need to write a matching outbound rule for return traffic
  - they operate at the ENI (network interface) level, so per-instance
*/

resource "aws_security_group" "ec2_sg" {
  name        = "ec2-ssh-restricted"
  description = "Allow SSH only from my IP, deny everything else inbound"
  vpc_id      = aws_vpc.main.id

  # Inbound: only SSH (port 22) from my specific IP
  # /32 = single IP address (just me, not the whole internet)
  ingress {
    description = "SSH from my IP only"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["76.78.246.155/32"]
  }

  # Outbound: allow all traffic out (so instance can download updates, reach AWS services, etc.)
  egress {
    description = "Allow all outbound traffic"
    from_port   = 0    #0 means all ports
    to_port     = 0
    protocol    = "-1" # -1 means all protocols (TCP, UDP, ICMP, etc.)
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "ec2-security-group"
  }
}
/*
Why no other ports?
  - No HTTP (80) or HTTPS (443) because this is not a web server
  - No RDP (3389) because this is Linux, not Windows
  - SSH is the only way to manage a Linux instance
  - Everything else is closed by default (SGs deny all inbound unless explicitly allowed)
*/


# =============================================
# NETWORK ACLs (subnet-level firewall)
# =============================================
/*
NACLs are STATELESS:
  - unlike Security Groups, you MUST create rules for BOTH directions
  - if you allow inbound SSH, you also need an outbound rule for the response
  - they operate at the subnet level, so they apply to ALL instances in that subnet
  - rules are evaluated in order by rule number (lowest first), first match wins
  - there is always an implicit deny-all rule (* rule) at the end
*/


# PUBLIC SUBNET NACL
# -----------------------------------------------
resource "aws_network_acl" "public_nacl" {
  vpc_id     = aws_vpc.main.id
  subnet_ids = [aws_subnet.public_subnet.id]

  # Rule 100: Allow SSH inbound from my IP only
  ingress {
    rule_no    = 100
    protocol   = "tcp"
    action     = "allow"
    cidr_block = "76.78.246.155/32"
    from_port  = 22
    to_port    = 22
  }

  # Rule 200: Allow ephemeral ports inbound (for return traffic from internet)
  # When your instance makes an outbound request, the response comes back on a random high port
  ingress {
    rule_no    = 200
    protocol   = "tcp"
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 1024
    to_port    = 65535
  }

  # Rule 300: Allow all inbound traffic from within the VPC
  # So public and private subnets can talk to each other
  ingress {
    rule_no    = 300
    protocol   = "-1"
    action     = "allow"
    cidr_block = "10.0.0.0/16"
    from_port  = 0
    to_port    = 0
  }

  # Rule 100: Allow all outbound traffic (responses, updates, etc.)
  egress {
    rule_no    = 100
    protocol   = "-1"
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 0
    to_port    = 0
  }

  tags = {
    Name = "public-nacl"
  }
}


# PRIVATE SUBNET NACL
# -----------------------------------------------
/*
The private subnet should NOT allow direct inbound traffic from the internet.
Only allow traffic from within the VPC (e.g., from a bastion host in the public subnet).
*/
resource "aws_network_acl" "private_nacl" {
  vpc_id     = aws_vpc.main.id
  subnet_ids = [aws_subnet.private_subnet.id]

  # Rule 100: Allow ALL inbound traffic from within the VPC only
  # This lets a bastion host in the public subnet SSH into private instances
  # 10.0.0.0/16 = only traffic from inside our VPC, NOT the internet
  ingress {
    rule_no    = 100
    protocol   = "-1"
    action     = "allow"
    cidr_block = "10.0.0.0/16"
    from_port  = 0
    to_port    = 0
  }
  # Everything else inbound is DENIED by the implicit * deny rule
  # This means 0.0.0.0/0 (internet) cannot reach the private subnet directly

  # Rule 100: Allow all outbound to the VPC (so instances can respond)
  egress {
    rule_no    = 100
    protocol   = "-1"
    action     = "allow"
    cidr_block = "10.0.0.0/16"
    from_port  = 0
    to_port    = 0
  }

  tags = {
    Name = "private-nacl"
  }
}


# =============================================
# AUTO SCALING
# =============================================
/*
Auto Scaling automatically adjusts the number of EC2 instances based on demand.
It has 3 parts:
  1. Launch Template — a blueprint for what kind of instance to create
  2. Auto Scaling Group (ASG) — manages how many instances should run
  3. Scaling Policy — the rule that triggers scaling (e.g., high CPU)
*/


# LAUNCH TEMPLATE
# -----------------------------------------------
# A reusable blueprint that tells the ASG what kind of EC2 instances to spin up
# Same config as our existing EC2: AMI, instance type, security group, key pair
resource "aws_launch_template" "my_template" {
  name          = "my-ec2-launch-template"
  description   = "Launch template for auto-scaled EC2 instances"
  image_id      = data.aws_ami.my_ami_linux.id  #same Amazon Linux 2 AMI
  instance_type = "t3.micro"                     #same instance type as our original EC2
  key_name      = aws_key_pair.my_key.key_name   #same SSH key for access

  # Attach our security group that only allows SSH from our IP
  network_interfaces {
    associate_public_ip_address = true  #so we can SSH into auto-scaled instances too
    security_groups             = [aws_security_group.ec2_sg.id]
  }

  # Tag instances created by the ASG so we can identify them in the console
  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "asg-ec2-instance"
    }
  }

  tags = {
    Name = "my-ec2-launch-template"
  }
}


# AUTO SCALING GROUP (ASG)
# -----------------------------------------------
/*
The ASG decides how many instances should be running at any time.
  - min_size: never go below this (always have at least 1 running)
  - max_size: never exceed this (cap at 4 even under heavy load)
  - desired_capacity: how many to start with (begin with 1)

The ASG uses the Launch Template to know WHAT to create,
and the Scaling Policy to know WHEN to create more.
*/
resource "aws_autoscaling_group" "my_asg" {
  name                = "my-auto-scaling-group"
  min_size            = 1    #minimum 1 instance always running
  max_size            = 4    #maximum 4 instances under heavy load
  desired_capacity    = 1    #start with 1 instance

  # Which subnets to launch instances in
  vpc_zone_identifier = [aws_subnet.public_subnet.id]

  # Use our launch template to create instances
  launch_template {
    id      = aws_launch_template.my_template.id
    version = "$Latest"  #always use the latest version of the template
  }

  # Tags to apply to the ASG itself
  tag {
    key                 = "Name"
    value               = "my-auto-scaling-group"
    propagate_at_launch = false  #this tag is for the ASG, not the instances
  }
}


# TARGET TRACKING SCALING POLICY
# -----------------------------------------------
/*
This policy tells the ASG WHEN to add or remove instances.
Target Tracking works like a thermostat:
  - You set a target (50% CPU utilization)
  - If average CPU across all instances goes ABOVE 50%, ASG adds instances
  - If average CPU drops BELOW 50%, ASG removes instances (down to min_size)
  - It constantly adjusts to keep CPU around the 50% target

ASGAverageCPUUtilization = average CPU usage across ALL instances in the ASG
*/
resource "aws_autoscaling_policy" "cpu_scaling" {
  name                   = "cpu-target-tracking"
  autoscaling_group_name = aws_autoscaling_group.my_asg.name
  policy_type            = "TargetTrackingScaling"

  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ASGAverageCPUUtilization"
    }
    target_value = 50.0  #scale when average CPU goes above 50%
  }
}


# =============================================
# AWS BACKUP (for EBS volume reliability)
# =============================================
/*
AWS Backup automates backups of your resources (EBS, RDS, S3, etc.)
It has 4 parts:
  1. IAM Role — gives the AWS Backup service permission to create backups
  2. Backup Vault — a secure container where backup snapshots are stored
  3. Backup Plan — the schedule (when and how often to back up, how long to keep them)
  4. Backup Selection — which resources to back up (our EBS volume)
*/


# IAM ROLE FOR AWS BACKUP
# -----------------------------------------------
# AWS Backup needs permission to access your resources (EBS, EC2, etc.)
# This role says "I trust the AWS Backup service to act on my behalf"
resource "aws_iam_role" "backup_role" {
  name = "aws-backup-role"

  # Trust policy: allows the AWS Backup service to assume this role
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "backup.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name = "aws-backup-role"
  }
}

# Attach the AWS managed policy that gives Backup permission to create backups
# This policy includes permissions for EBS snapshots, EC2 tags, etc.
resource "aws_iam_role_policy_attachment" "backup_policy" {
  role       = aws_iam_role.backup_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForBackup"
}


# BACKUP VAULT
# -----------------------------------------------
# A secure container where all backup snapshots are stored
# Think of it like a folder specifically for backups
resource "aws_backup_vault" "my_vault" {
  name = "my-backup-vault"

  tags = {
    Name = "my-backup-vault"
  }
}


# BACKUP PLAN
# -----------------------------------------------
# Defines the schedule: how often to back up and how long to keep backups
resource "aws_backup_plan" "my_plan" {
  name = "my-ebs-backup-plan"

  rule {
    rule_name         = "daily-ebs-backup"
    target_vault_name = aws_backup_vault.my_vault.name

    # Run backup every day at 5:00 AM UTC
    # cron format: minute hour day month weekday year
    schedule = "cron(0 5 * * ? *)"

    # Keep each backup for 7 days, then automatically delete it
    # This prevents old backups from piling up and costing money
    lifecycle {
      delete_after = 7
    }
  }

  tags = {
    Name = "my-ebs-backup-plan"
  }
}


# BACKUP SELECTION
# -----------------------------------------------
# Tells the Backup Plan WHICH resources to back up
# We're targeting our specific EBS volume by its ARN
resource "aws_backup_selection" "my_selection" {
  name         = "my-ebs-backup-selection"
  plan_id      = aws_backup_plan.my_plan.id
  iam_role_arn = aws_iam_role.backup_role.arn

  # List of resource ARNs to back up — just our EBS volume
  resources = [
    aws_ebs_volume.my_volume.arn
  ]
}


