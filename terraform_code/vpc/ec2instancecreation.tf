provider "aws" {
    region = "us-east-1"
  
}
variable "ansible_user_data" {
  default = <<-EOF
              #!/bin/bash
              apt-get update -y
              apt-get install -y software-properties-common
              add-apt-repository --yes --update ppa:ansible/ansible
              apt-get install -y ansible
              # Additional software installation steps can be added here
              apt-get install git -y 
              cd /opt 
              git clone https://github.com/ravipramoth/devops_infra.git
            EOF
}

resource "aws_instance" "demo-server" {
    ami= "ami-0fc5d935ebf8bc3bc"
    instance_type = "t2.medium"
    key_name = "Comman_Key"
    vpc_security_group_ids = [aws_security_group.demo-sg.id]
    subnet_id = aws_subnet.dpp-public-subnet-01.id
    for_each = toset(["jenkins-master","build-server", "ansible"])
    
    tags ={
        Name = "${each.key}"
    }

    user_data = each.key == "ansible" ? var.ansible_user_data : null
}



resource "aws_security_group" "demo-sg" {
    name = "demo-sg"
    description = "ssh access"
    vpc_id = aws_vpc.dpp-vpc.id
    
    ingress {
        description = "ssh-access"
        from_port = 22
        to_port = 22
        protocol = "tcp"
        cidr_blocks = [ "0.0.0.0/0" ]
    }
    ingress {
        description = "jenkins_access"
        from_port = 8080
        to_port = 8080
        protocol = "tcp"
        cidr_blocks = ["0.0.0.0/0"]
    }
    egress{
        from_port = 0
        to_port = 0
        protocol = "-1"
        cidr_blocks = [ "0.0.0.0/0" ]
        ipv6_cidr_blocks = [ "::/0" ]
    }
  tags = {
    name = "ssh=keys"
  }
}

resource "aws_vpc" "dpp-vpc" {
    cidr_block = "10.1.0.0/16"
    tags = {
        name = "ddp_vpc"

    }
  
}

resource "aws_subnet" "dpp-public-subnet-01" {
    vpc_id = aws_vpc.dpp-vpc.id
    cidr_block = "10.1.1.0/24"
    map_public_ip_on_launch = "true"
    availability_zone = "us-east-1a"
    tags = {
        name = "dpp-public-subnet-01"
    } 
}

resource "aws_subnet" "dpp-public-subnet-02"{
    vpc_id = aws_vpc.dpp-vpc.id 
    cidr_block = "10.1.2.0/24"
    map_public_ip_on_launch = "true"
    availability_zone = "us-east-1b"
    tags ={
        name = "dpp-public-subney-02"
    }     
}

resource "aws_internet_gateway" "dpp-igw" {
    vpc_id = aws_vpc.dpp-vpc.id 
    tags = {
      name ="dpp.igw"
    }
}

resource "aws_route_table" "dpp-public-rt" {
    vpc_id = aws_vpc.dpp-vpc.id 
    route  {
        cidr_block = "0.0.0.0/0"
        gateway_id = aws_internet_gateway.dpp-igw.id
        
    }
  }
  resource "aws_route_table_association" "dpp-rta-public-subnet-01"{
    subnet_id = aws_subnet.dpp-public-subnet-01.id
    route_table_id = aws_route_table.dpp-public-rt.id
  }

  resource "aws_route_table_association" "dpp-rta-public-subnet-02" {
    subnet_id = aws_subnet.dpp-public-subnet-02.id
    route_table_id = aws_route_table.dpp-public-rt.id
 
  }

    module "sgs" {
    source = "../sg_eks"
    vpc_id     =     aws_vpc.dpp-vpc.id
 }

  module "eks" {
       source = "../eks"
       vpc_id     =     aws_vpc.dpp-vpc.id
       subnet_ids = [aws_subnet.dpp-public-subnet-01.id,aws_subnet.dpp-public-subnet-02.id]
       sg_ids = module.sgs.security_group_public
 }