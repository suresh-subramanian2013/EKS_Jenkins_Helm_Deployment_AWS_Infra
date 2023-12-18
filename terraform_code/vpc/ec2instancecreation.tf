provider "aws" {
    region = "us-east-1"
    profile = "sk"
  
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
              git clone https://github.com/suresh-subramanian2013/EKS_Jenkins_Helm_Deployment_AWS_Infra.git
              sudo chmod 700 EKS_Jenkins_Helm_Deployment_AWS_Infra/Ansible/demo.pem
              sudo ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook -i EKS_Jenkins_Helm_Deployment_AWS_Infra/Ansible/host EKS_Jenkins_Helm_Deployment_AWS_Infra/Ansible/ansible-master-jenkins-setup.yaml
              sudo ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook -i EKS_Jenkins_Helm_Deployment_AWS_Infra/Ansible/host EKS_Jenkins_Helm_Deployment_AWS_Infra/Ansible/build-server-setup.yaml
            EOF
}
resource "aws_iam_instance_profile" "build_server" {
  name = "build-server-profile"
  role = aws_iam_role.build_server.name
}

resource "aws_iam_role" "build_server" {
  name = "build-server-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Effect = "Allow",
        Principal = {
          Service = "ec2.amazonaws.com",
        },
      },
    ],
  })
  // Add policy statements for EKS permissions
  inline_policy {
    name = "eks-cluster-policy"
    policy = jsonencode({
      Version = "2012-10-17",
      Statement = [
        {
          Action = [
            "eks:DescribeCluster",
            "eks:DescribeNodegroup",
            "eks:ListNodegroups",
            "eks:CreateNodegroup",
            "eks:UpdateNodegroupConfig",
            "eks:DeleteNodegroup",
            "eks:TagResource",
            "eks:UntagResource",
          ]
          Effect = "Allow",
          Resource = "*",
        },
        // Add other EKS-related permissions if needed
      ],
    })
  }
}

resource "aws_iam_role_policy_attachment" "eks_access_attachment" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"  # Replace with the ARN of your EKS policy
  role       = aws_iam_role.build_server.name
}

resource "aws_instance" "demo-server" {
    ami= "ami-0fc5d935ebf8bc3bc"
    instance_type = "t2.medium"
    key_name = "demo"
    vpc_security_group_ids = [aws_security_group.demo-sg.id]
    subnet_id = aws_subnet.dpp-public-subnet-01.id
    private_ip = each.key == "jenkins-master" ? "10.1.1.10" : each.key == "build-server" ? "10.1.1.13" : each.key == "ansible" ? "10.1.1.12" : null
    for_each = toset(["jenkins-master","build-server", "ansible"])
    
    tags ={
        Name = "${each.key}"
    }

    user_data = each.key == "ansible" ? var.ansible_user_data : null
    iam_instance_profile = each.key == "build-server" ? aws_iam_instance_profile.build_server.id : null
    depends_on = [module.eks]
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