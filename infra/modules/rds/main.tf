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

  instance_class    = var.instance_class
  allocated_storage = var.allocated_storage
  storage_type      = "gp3"

  db_name  = var.database_name
  username = var.database_user
  password = random_password.db_password.result

  db_subnet_group_name   = aws_db_subnet_group.app.name
  vpc_security_group_ids = [aws_security_group.rds.id]

  publicly_accessible = false

  multi_az = var.multi_az # false for dev/test; set true for prod

  backup_retention_period = var.backup_retention_period
  backup_window           = "03:00-04:00"
  maintenance_window      = "sun:04:30-sun:05:30"

  skip_final_snapshot = var.skip_final_snapshot # true for dev/test convenience; false for prod safety

  # Required whenever skip_final_snapshot is false (prod) — AWS
  # needs a name for the snapshot it takes on destroy. Ignored
  # entirely when skip_final_snapshot is true (dev/test).
  final_snapshot_identifier = var.skip_final_snapshot ? null : "${var.instance_identifier}-final-${formatdate("YYYYMMDDhhmmss", timestamp())}"

  deletion_protection = var.deletion_protection # false for dev/test; true for prod

  tags = {
    Name = var.instance_identifier
  }

  # final_snapshot_identifier embeds a timestamp so it's unique
  # each time it would actually be used (at destroy). Without this
  # lifecycle block, Terraform would show a spurious diff on every
  # single plan, since timestamp() re-evaluates every run.
  lifecycle {
    ignore_changes = [final_snapshot_identifier]
  }
}
