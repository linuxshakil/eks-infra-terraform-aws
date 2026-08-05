############################################################
# DB Subnet Group
#
# On GCP, Cloud SQL's "private_network" peered directly into
# the VPC (private services access). The AWS RDS model is a
# bit simpler — RDS's ENI is created straight inside the
# subnets you give it, no separate peering connection needed.
# That's why our "network" module has no peering.tf like the
# GCP version did — this RDS module just takes subnet_ids and
# places its ENI inside the private subnets on its own.
############################################################

resource "aws_db_subnet_group" "app" {
  name       = "${var.instance_identifier}-subnet-group"
  subnet_ids = var.private_subnet_ids

  tags = {
    Name = "${var.instance_identifier}-subnet-group"
  }
}

############################################################
# Security Group
#
# On GCP, Cloud SQL's private IP was already VPC-internal, so
# no firewall rule was needed in that demo. On AWS, RDS always
# sits behind a Security Group — we allow only port 3306
# (MySQL) from the EKS node security group, nothing else. This
# is actually more explicit and secure than the GCP version.
############################################################

resource "aws_security_group" "rds" {
  name        = "${var.instance_identifier}-sg"
  description = "Allow MySQL from EKS nodes only"
  vpc_id      = var.vpc_id

  ingress {
    description     = "MySQL from EKS worker nodes"
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [var.eks_node_security_group_id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.instance_identifier}-sg"
  }
}

############################################################
# RDS MySQL Instance
#
# GCP: google_sql_database_instance (MYSQL_8_0, tier db-custom-1-3840,
# ZONAL availability, PD_SSD 20GB, automated backups on).
#
# AWS equivalent: db.t3.medium instance class, engine mysql
# 8.0, gp3 storage, Multi-AZ off (learning tier — turn on for
# real production), automated backups enabled by default.
############################################################

resource "aws_db_instance" "app" {
  identifier     = var.instance_identifier
  engine         = "mysql"
  engine_version = "8.0"

  instance_class    = "db.t3.medium"
  allocated_storage = 20
  storage_type      = "gp3"

  db_name  = var.database_name
  username = var.database_user
  password = random_password.db_password.result

  db_subnet_group_name   = aws_db_subnet_group.app.name
  vpc_security_group_ids = [aws_security_group.rds.id]

  publicly_accessible = false

  multi_az = false # fine for learning/demo; set true for real production (like upgrading GCP's ZONAL to REGIONAL)

  backup_retention_period = 7
  backup_window           = "03:00-04:00"
  maintenance_window      = "sun:04:30-sun:05:30"

  skip_final_snapshot = true # convenient for learning; for production set this false and add final_snapshot_identifier

  deletion_protection = false # same as the GCP version's deletion_protection = false, kept simple for this demo

  tags = {
    Name = var.instance_identifier
  }
}
