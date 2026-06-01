# ── Data source: look up available AZs in the region ──────────────────────────
data "aws_availability_zones" "available" {
  state = "available"
  # This dynamically fetches the AZs in your region.
  # You never hardcode "eu-west-1a" — if AWS adds or removes AZs your code still works.
}

# ── VPC ───────────────────────────────────────────────────────────────────────
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  # DNS hostnames must be on so EC2 instances get a public DNS name.
  # Without this, connecting to your instance by hostname won't work.
  enable_dns_support = true

  tags = {
    Name        = "${var.project}-${var.env}"
    Project     = var.project
    Environment = var.env
  }
}

# ── Public subnets ────────────────────────────────────────────────────────────
resource "aws_subnet" "public" {
  count = length(var.public_subnet_cidrs)
  # count creates one subnet per CIDR you defined — currently 2.

  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = true
  # map_public_ip_on_launch = true means any EC2 launched in this subnet
  # automatically gets a public IP. This is what lets it reach the internet
  # without a NAT gateway.

  tags = {
    Name        = "${var.project}-${var.env}-public-${count.index + 1}"
    Project     = var.project
    Environment = var.env
    Type        = "public"
    # These tags are required later when EKS needs to discover which subnets
    # to use for load balancers. Adding them now costs nothing.
    "kubernetes.io/role/elb" = "1"
  }
}

# ── Internet Gateway ──────────────────────────────────────────────────────────
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
  # The internet gateway is what connects your VPC to the internet.
  # Without this, nothing in your VPC can reach the outside world.
  # Unlike a NAT gateway, this is completely free.

  tags = {
    Name        = "${var.project}-${var.env}-igw"
    Project     = var.project
    Environment = var.env
  }
}

# ── Route table ───────────────────────────────────────────────────────────────
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  # A route table is a set of rules that say "if traffic is going to X, send it to Y".

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
    # 0.0.0.0/0 means "all traffic".
    # This rule says: anything going to the internet → send it through the IGW.
    # Without this rule, your instances have no path to the internet even though
    # the IGW exists.
  }

  tags = {
    Name        = "${var.project}-${var.env}-public-rt"
    Project     = var.project
    Environment = var.env
  }
}

# ── Route table association ───────────────────────────────────────────────────
resource "aws_route_table_association" "public" {
  count = length(aws_subnet.public)
  # One association per subnet — connects each subnet to the route table above.

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
  # Without this association the subnet exists but has no route to the internet.
  # The VPC has a default route table but it has no internet route.
  # You must explicitly associate subnets with a route table that has the IGW route.
}
