#Generate SSH key pair 
resource "tls_private_key" "cloud_key" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

# Add key for ssh connection
resource "aws_key_pair" "cloud_key" {
  key_name   = "cloud_key"
  public_key = tls_private_key.cloud_key.public_key_openssh
}

resource "aws_vpc" "aap_vpc" {
  cidr_block           = "10.1.0.0/16"
  enable_dns_hostnames = "true"
  instance_tenancy     = "default"

  tags = {
    Name      = "aap-VPC"
    Terraform = "true"
  }
}

resource "aws_internet_gateway" "aap_igw" {
  vpc_id = aws_vpc.aap_vpc.id

  tags = {
    Name      = "AAP_IGW"
    Terraform = "true"
  }
}

resource "aws_route_table" "aap_pub_igw" {
  vpc_id = aws_vpc.aap_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.aap_igw.id
  }

  tags = {
    Name      = "AAP-RouteTable"
    Terraform = "true"
  }
}

resource "aws_subnet" "aap_subnet" {
  cidr_block              = "10.1.0.0/24"
  map_public_ip_on_launch = "true"
  vpc_id                  = aws_vpc.aap_vpc.id

  tags = {
    Name      = "AAP-Subnet"
    Terraform = "true"
  }
}

resource "aws_route_table_association" "aap_rt_subnet_public" {
  subnet_id      = aws_subnet.aap_subnet.id
  route_table_id = aws_route_table.aap_pub_igw.id
}

resource "aws_security_group" "aap_security_group" {
  name        = "aap-sg"
  description = "Security Group for AAP webserver"
  vpc_id      = aws_vpc.aap_vpc.id

  tags = {
    Name      = "AAP-Security-Group"
    Terraform = "true"
  }
}

resource "aws_security_group_rule" "http_ingress_access" {
  type              = "ingress"
  from_port         = 80
  to_port           = 80
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.aap_security_group.id
}

resource "aws_security_group_rule" "ssh_ingress_access" {
  type              = "ingress"
  from_port         = 22
  to_port           = 22
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.aap_security_group.id
}

resource "aws_security_group_rule" "postgresql_ingress_access" {
  type              = "ingress"
  from_port         = 5432
  to_port           = 5432
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.aap_security_group.id
}

resource "aws_security_group_rule" "redis_ingress_access" {
  type              = "ingress"
  from_port         = 6379
  to_port           = 6379
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.aap_security_group.id
}

resource "aws_security_group_rule" "secure_ingress_access" {
  type              = "ingress"
  from_port         = 8433
  to_port           = 8433
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.aap_security_group.id
}

resource "aws_security_group_rule" "https_ingress_access" {
  type              = "ingress"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.aap_security_group.id
}

resource "aws_security_group_rule" "grpc_ingress_access" {
  type              = "ingress"
  from_port         = 50051
  to_port           = 50051
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.aap_security_group.id
}

resource "aws_security_group_rule" "egress_access" {
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.aap_security_group.id
}

# Set ami for ec2 instance
data "aws_ami" "rhel" {
  most_recent = true
  filter {
    name   = "name"
    values = ["RHEL-9.5.0_HVM*"]
  }
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
  owners = ["309956199498"]
}

resource "aws_instance" "aap_instance" {
  instance_type               = "m6a.xlarge"
  vpc_security_group_ids      = [aws_security_group.aap_security_group.id]
  associate_public_ip_address = true
  key_name                    = module.key_pair.key_pair_name
  #user_data                   = file("user_data.txt")
  ami               = data.aws_ami.rhel.id
  subnet_id         = aws_subnet.aap_subnet.id

  # Specify the root block device to adjust volume size
  root_block_device {
    volume_size           = 150   # Set desired size in GB (e.g., 100 GB)
    volume_type           = "gp3" # Optional: Specify volume type (e.g., "gp3" for general purpose SSD)
    delete_on_termination = true  # Optional: Automatically delete volume on instance termination
  }
  

  tags = {
    Name      = "aap-controller"
    Terraform = "true"
  }
}

module "key_pair" {
  source  = "terraform-aws-modules/key-pair/aws"
  version = "2.0.2"

  key_name           = "aap-testing"
  create_private_key = true
}

resource "local_sensitive_file" "key_pair_pem" {
  filename = "${path.root}/../${module.key_pair.key_pair_name}.pem"
  file_permission = "400"
  content = module.key_pair.private_key_pem
}

resource "terraform_data" "aap_subscription_manager" {
  connection {
    type = "ssh"
    user = "ec2-user"
    host = aws_instance.aap_instance.public_ip
    private_key = module.key_pair.private_key_pem
    timeout = "10m"
  }
  provisioner "remote-exec" {
    inline = [ 
      "sudo subscription-manager register --username ${var.aap_red_hat_username} --password ${var.aap_red_hat_password} --auto-attach",
      "sudo subscription-manager config --rhsm.manage_repos=1"#,
      #"yes | sudo dnf upgrade"
      ]
  }
}

# Create a Security Group for EFS
resource "aws_security_group" "efs_security_group" {
  name        = "efs-sg"
  description = "Allow EFS access"
  vpc_id      = aws_vpc.aap_vpc.id

  ingress {
    from_port   = 2049
    to_port     = 2049
    protocol    = "tcp"
    cidr_blocks = ["10.1.0.0/16"] # Adjust CIDR block as needed
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name      = "EFS-Security-Group"
    Terraform = "true"
  }
}

# Create an EFS File System
resource "aws_efs_file_system" "efs" {
  creation_token   = "aap-efs"
  performance_mode = "generalPurpose" # or "maxIO" for high IOPS
  lifecycle_policy {
    transition_to_ia = "AFTER_30_DAYS" # Optional: Move files to Infrequent Access after 30 days
  }

  tags = {
    Name      = "AAP-EFS"
    Terraform = "true"
  }
}

# Create Mount Targets for EFS
resource "aws_efs_mount_target" "efs_mount_target_a" {
  file_system_id  = aws_efs_file_system.efs.id
  subnet_id       = aws_subnet.aap_subnet.id
  security_groups = [aws_security_group.efs_security_group.id]
}

# resource "null_resource" "hostname_update" {
#   depends_on = [aws_instance.aap_instance]

#   provisioner "remote-exec" {
#     inline = [
#       # Register Red Hat Host
#       "sudo rhc connect --activation-key=<activation_key_name> --organization=<organization_ID>",

#       # Ensure stuff is installed
#       "sudo dnf install -y ansible-core wget git-core rsync vim",

#       # Set hostname
#       "sudo hostnamectl set-hostname ${aws_instance.aap_instance.public_dns}",

#       # Download and extract the setup file
#       "wget https://github.com/r3dact3d/AAP-2.5-Containerized-on-AWS/raw/refs/heads/ansible/post_data/ansible-automation-platform-containerized-setup-<AAP_VERSION>.tar.gz",
#       "file ansible-automation-platform-containerized-setup-<AAP_VERSION>.tar.gz",
#       "tar xfvz ansible-automation-platform-containerized-setup-<AAP_VERSION>.tar.gz",
#       "sleep 45",

#       # Setup SSH Keys
#       "echo ${tls_private_key.cloud_key.private_key_pem} >> /home/ec2-user/.ssh/cloud_keys",
#       "chmod 0644 /home/ec2-user/.ssh/cloud_keys",

#       # Stage the manifest files
#       "wget https://github.com/r3dact3d/AAP-2.5-Containerized-on-AWS/raw/refs/heads/ansible/post_data/manifest_AAP_Demo.zip",
#       "sleep 15",

#       # Configure inventory
#       "cd ansible-automation-platform-containerized-setup-<AAP_VERSION>",
#       "wget -O inventory-growth https://raw.githubusercontent.com/r3dact3d/AAP-2.5-Containerized-on-AWS/refs/heads/ansible/post_data/inventory-growth-custom",
#       "sleep 15",
#       "sed -i 's/<set your own>/new-install-password/g' inventory-growth",
#       "sed -i 's/aap.example.org/${aws_instance.aap_instance.public_dns}/g' inventory-growth",
#       "sed -i 's/<your RHN username>/rhn_user/g' inventory-growth",
#       "sed -i 's/<your RHN password>/rhn_pass/g' inventory-growth",
#       #"sed -i 's/<path_to_nfs_share>/${aws_efs_file_system.efs.dns_name}/g' inventory-growth",
#       "sleep 15",

#       "ansible-playbook -i inventory-growth ansible.containerized_installer.install -c local --private-key /home/ec2-user/.ssh/cloud_keys",
#     ]


#     connection {
#       type        = "ssh"
#       host        = aws_instance.aap_instance.public_ip
#       user        = "ec2-user"
#       private_key = tls_private_key.cloud_key.private_key_pem
#     }
#   }
# }

# Add created ec2 instance to ansible inventory
resource "ansible_host" "aap_instance" {
  name   = aws_instance.aap_instance.public_dns
  groups = ["gateway"]
  variables = {
    ansible_user                 = "ec2-user",
    ansible_ssh_private_key_file = "~/.ssh/id_rsa",
    ansible_python_interpreter   = "/usr/bin/python3",
  }
}


