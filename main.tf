provider "aws" {
  region = "eu-central-1"  # Change to your preferred AWS region
  access_key = "******"
  secret_key = "****************"
  alias = "eu"
}

# Generate a secure username and password for the database
resource "random_password" "db_password" {
  length           = 16
  special          = true
  override_special = "_%"  # Allow only specific special characters
}

resource "random_string" "db_username" {
  length  = 8
  upper   = false
  special = false
}

# Store the generated username and password in AWS Secrets Manager
resource "aws_secretsmanager_secret" "db_credentials" {
  name        = "rds-postgres-credentials"
  description = "Database credentials for the RDS PostgreSQL instance"
}

resource "aws_secretsmanager_secret_version" "db_credentials_secret" {
  secret_id = aws_secretsmanager_secret.db_credentials.id
  secret_string = jsonencode({
    username = random_string.db_username.result
    password = random_password.db_password.result
  })
}

# Create an RDS Subnet Group
resource "aws_db_subnet_group" "rds_subnet_group" {
  name       = "rds-subnet-group"
  subnet_ids = ["subnet-b5f70dc9", "subnet-32ef6058", "subnet-42e1280e"]  # Replace with your VPC subnet IDs

  tags = {
    Name = "rds-subnet-group"
  }
}

# Security Group for RDS allowing access to PostgreSQL port (5432)
resource "aws_security_group" "rds_sg" {
  name_prefix = "rds-sg"
  description = "Security group for RDS PostgreSQL instance"
  vpc_id      = "vpc-c841e5a2"  # Replace with your VPC ID

  ingress {
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]  # Adjust for specific IPs
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "rds-postgres-sg"
  }
}

# IAM Role and Policy for Enhanced Monitoring
resource "aws_iam_role" "rds_monitoring_role" {
  name = "rds-monitoring-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Principal = {
          Service = "monitoring.rds.amazonaws.com"
        },
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "rds_monitoring_role_policy" {
  role       = aws_iam_role.rds_monitoring_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}

# Provision an RDS PostgreSQL instance
resource "aws_db_instance" "postgres_instance" {
  allocated_storage      = 20
  engine                 = "postgres"
  engine_version         = "15"
  instance_class         = "db.t3.micro"  # Change to suit your instance needs
  db_name                = "mydatabase"
  username               = random_string.db_username.result
  password               = random_password.db_password.result
  parameter_group_name   = "default.postgres15"  # Ensure compatibility with your version
  port                   = 5432
  db_subnet_group_name   = aws_db_subnet_group.rds_subnet_group.name
  vpc_security_group_ids = [aws_security_group.rds_sg.id]
  skip_final_snapshot    = true
  # Enable Enhanced Monitoring
  monitoring_interval = 60  # Set interval to 60 seconds (valid values: 1, 5, 10, 15, 30, 60)
  monitoring_role_arn = aws_iam_role.rds_monitoring_role.arn
  # Enable Deletion Protection
  deletion_protection = true

  tags = {
    Name = "postgres-rds-instance"
  }
}



# Output the database credentials from Secrets Manager
output "db_credentials_secret_arn" {
  value       = aws_secretsmanager_secret.db_credentials.arn
  description = "The ARN of the Secrets Manager secret containing the database credentials."
}

output "db_endpoint" {
  value       = aws_db_instance.postgres_instance.endpoint
  description = "The endpoint of the PostgreSQL RDS instance."
}
