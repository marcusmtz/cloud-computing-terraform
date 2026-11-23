data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  selected_azs = slice(data.aws_availability_zones.available.names, 0, 2)

  subnet_definitions = {
    public_a  = { index = 0, public = true }
    public_b  = { index = 1, public = true }
    private_a = { index = 2, public = false }
    private_b = { index = 3, public = false }
  }
}

resource "aws_vpc" "norcom" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "${var.project_name}-${var.environment}-vpc"
  }
}

resource "aws_internet_gateway" "norcom" {
  vpc_id = aws_vpc.norcom.id

  tags = {
    Name = "${var.project_name}-${var.environment}-igw"
  }
}

resource "aws_subnet" "tier" {
  for_each = local.subnet_definitions

  vpc_id                  = aws_vpc.norcom.id
  cidr_block              = cidrsubnet(var.vpc_cidr, 4, each.value.index)
  availability_zone       = local.selected_azs[each.value.index % 2]
  map_public_ip_on_launch = false

  tags = {
    Name = "${var.project_name}-${var.environment}-${replace(each.key, "_", "-")}-${local.selected_azs[each.value.index % 2]}"
    Tier = each.value.public ? "edge" : "private"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.norcom.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.norcom.id
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-public-rt"
  }
}

resource "aws_route_table_association" "public" {
  for_each = {
    for name, subnet in aws_subnet.tier : name => subnet
    if local.subnet_definitions[name].public
  }

  subnet_id      = each.value.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.norcom.id

  tags = {
    Name = "${var.project_name}-${var.environment}-private-rt"
  }
}

resource "aws_route_table_association" "private" {
  for_each = {
    for name, subnet in aws_subnet.tier : name => subnet
    if !local.subnet_definitions[name].public
  }

  subnet_id      = each.value.id
  route_table_id = aws_route_table.private.id
}

