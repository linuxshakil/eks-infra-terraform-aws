############################################################
# VPC
#
# In GCP we used "google_compute_network" (auto_create_subnetworks
# = false) and created subnets and secondary ranges ourselves.
# On AWS, the CIDR must be fixed when you create the VPC, and
# subnets are always a separate resource (same as GCP).
#
# There is no direct AWS equivalent of secondary ranges (pods-range
# / services-range) because EKS's default networking mode is
# "VPC-CNI" — pods get real IPs straight from the VPC subnet
# (similar to GKE's "VPC-Native" mode, but without a separate
# secondary range). That's why we've made the subnets generously
# sized.
############################################################

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "${var.cluster_name}-vpc"
    # This tag is how EKS and the AWS Load Balancer Controller
    # recognize which VPC belongs to this cluster
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
  }
}

data "aws_availability_zones" "available" {
  state = "available"
}

############################################################
# Public Subnets  (NAT Gateway + internet-facing Load Balancer)
############################################################

resource "aws_subnet" "public" {
  count = var.az_count

  vpc_id                  = aws_vpc.main.id
  cidr_block              = cidrsubnet(var.vpc_cidr, 4, count.index)
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.cluster_name}-public-${count.index}"
    # These tags tell the AWS Load Balancer Controller and EKS
    # which subnets can be used for public ALBs. GCP didn't need
    # this kind of explicit tagging because the GCE Ingress
    # controller is wired directly into Google's own control plane.
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
    "kubernetes.io/role/elb"                    = "1"
  }
}

############################################################
# Private Subnets  (EKS worker nodes + RDS)
############################################################

resource "aws_subnet" "private" {
  count = var.az_count

  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 4, count.index + var.az_count)
  availability_zone = data.aws_availability_zones.available.names[count.index]

  tags = {
    Name = "${var.cluster_name}-private-${count.index}"
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
    "kubernetes.io/role/internal-elb"           = "1"
  }
}

############################################################
# Internet Gateway  (implicit on GCP; an explicit resource on AWS)
############################################################

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.cluster_name}-igw"
  }
}

############################################################
# NAT Gateway
#
# GCP's "google_compute_router_nat" (Cloud NAT) is the equivalent
# of AWS's "aws_nat_gateway" here. Worker nodes in the private
# subnet reach the internet (docker pulls, package updates,
# outbound ECR calls) through this, without needing a public IP.
############################################################

resource "aws_eip" "nat" {
  domain = "vpc"

  tags = {
    Name = "${var.cluster_name}-nat-eip"
  }
}

resource "aws_nat_gateway" "main" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public[0].id

  tags = {
    Name = "${var.cluster_name}-nat"
  }

  depends_on = [aws_internet_gateway.main]
}

############################################################
# Route Tables
############################################################

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name = "${var.cluster_name}-public-rt"
  }
}

resource "aws_route_table_association" "public" {
  count = var.az_count

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main.id
  }

  tags = {
    Name = "${var.cluster_name}-private-rt"
  }
}

resource "aws_route_table_association" "private" {
  count = var.az_count

  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}
