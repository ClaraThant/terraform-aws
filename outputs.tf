output "vpc_id" {
  description = "ID of the VPC"
  value       = aws_vpc.main.id
}

output "public_subnet_id" {
  description = "ID of the Public Subnet"
  value       = aws_subnet.public_subnet.id
}

output "private_subnet_id" {
  description = "ID of the Private Subnet"
  value       = aws_subnet.private_subnet.id
}

output "ec2_instance_id" {
  description = "ID of the EC2 Instance"
  value       = aws_instance.my_instance.id
}

output "ec2_private_ip" {
  description = "Private IP of the EC2 Instance"
  value       = aws_instance.my_instance.private_ip
}

output "ec2_public_ip" {
  description = "Public IP of the EC2 Instance (use this to SSH in)"
  value       = aws_instance.my_instance.public_ip
}

output "ebs_volume_id" {
  description = "ID of the EBS Volume"
  value       = aws_ebs_volume.my_volume.id
}

output "s3_bucket_name" {
  description = "Name of the S3 Bucket"
  value       = aws_s3_bucket.my_bucket.bucket
}

output "security_group_id" {
  description = "ID of the EC2 Security Group"
  value       = aws_security_group.ec2_sg.id
}

output "public_nacl_id" {
  description = "ID of the Public Subnet NACL"
  value       = aws_network_acl.public_nacl.id
}

output "private_nacl_id" {
  description = "ID of the Private Subnet NACL"
  value       = aws_network_acl.private_nacl.id
}

output "launch_template_id" {
  description = "ID of the Launch Template"
  value       = aws_launch_template.my_template.id
}

output "asg_name" {
  description = "Name of the Auto Scaling Group"
  value       = aws_autoscaling_group.my_asg.name
}

output "backup_vault_name" {
  description = "Name of the AWS Backup Vault"
  value       = aws_backup_vault.my_vault.name
}

output "backup_plan_id" {
  description = "ID of the AWS Backup Plan"
  value       = aws_backup_plan.my_plan.id
}
