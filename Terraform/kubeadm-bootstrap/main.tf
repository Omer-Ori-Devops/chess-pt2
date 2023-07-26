#------------------------------------------------------------------------------#
# Common local values
#------------------------------------------------------------------------------#

locals {
  tags = merge(var.tags, { "terraform-kubeadm:cluster" = var.cluster_name })
}

#------------------------------------------------------------------------------#
# Key pair
#------------------------------------------------------------------------------#

# Performs 'ImportKeyPair' API operation (not 'CreateKeyPair')
resource "aws_key_pair" "main" {
  key_name_prefix = "${var.cluster_name}-"
  public_key      = file(var.public_key_file)
  tags            = local.tags
}

#------------------------------------------------------------------------------#
# IAM 
#------------------------------------------------------------------------------#

resource "aws_iam_role" "k8_role" {
  name = "k8_role"

  # Terraform's "jsonencode" function converts a
  # Terraform expression result to valid JSON syntax.
  assume_role_policy = jsonencode({
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "ssm:Describe*",
                "ssm:Get*",
                "ssm:List*"
            ],
            "Resource": "*"
        }
    ]
})

  tags = {
    tag-key = "k8_role"
  }
}
resource "aws_iam_instance_profile" "k8_profile" {
  name = "k8_profile"
  role = aws_iam_role.k8_role
}

#lamda role here-

#------------------------------------------------------------------------------#
# Lambda + ssm
#------------------------------------------------------------------------------#
resource "random_string" "jwt_secret" {
  length  = 32
  special = false
  upper   = false
  number  = false
}
resource "random_string" "Message_key_creator" {
  length  = 32
  special = false
  upper   = false
  number  = false
}

resource "aws_ssm_parameter" "jwt_secret_parameter" {
  name  = "JWT_SECRET"
  type  = "SecureString"
  value = random_string.jwt_secret.result # This will be replaced when the Lambda function runs

}
resource "aws_ssm_parameter" "MESSAGE_KEY_parameter" {
  name  = "MESSAGE_KEY"
  type  = "SecureString"
  value = random_string.Message_key_creator

}


resource "aws_iam_role" "lambda_role" {
  name = "lambda_ssm_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_policy_attachment" "lambda_ssm_attachment" {
  name       = "lambda_ssm_attachment"
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMFullAccess" # Or create a custom policy with the necessary permissions
  roles      = [aws_iam_role.lambda_role.name]
}

resource "aws_lambda_function" "JWT_TOKEN_CREATER" {
  function_name = "JWT_TOKEN_CREATER_lambda_function"
  role          = aws_iam_role.lambda_role.arn
  handler       = "index.lambda_handler"
  runtime       = "python3.10" 

 

  // Lambda function code (Python)
  source_code = <<-PYTHON
import boto3
import os
import secrets

def lambda_handler(event, context):
    # Create an instance of the AWS Systems Manager service
    ssm = boto3.client('ssm')

    try:
        # Generate a random 32-byte string
        jwt_secret = secrets.token_hex(32)

        # Update the parameter value in AWS Systems Manager Parameter Store
        response = ssm.put_parameter(
            Name='JWT_SECRET',
            Value=jwt_secret,
            Type='SecureString',
            Overwrite=True
        )

        return {
            'statusCode': 200,
            'body': 'JWT_SECRET parameter updated successfully.'
        }
    except Exception as e:
        print('Error updating JWT_SECRET parameter:', e)
        return {
            'statusCode': 500,
            'body': 'Error updating JWT_SECRET parameter.'
        }
  PYTHON
}

resource "aws_lambda_function" "Message_key_creator" {
  function_name = "Message_key_creator_lambda_function"
  role          = aws_iam_role.lambda_role.arn
  handler       = "index.lambda_handler"
  runtime       = "python3.10" 

 

  // Lambda function code (Python)
  source_code = <<-PYTHON
import boto3
import os
import secrets

def lambda_handler(event, context):
    # Create an instance of the AWS Systems Manager service
    ssm = boto3.client('ssm')

    try:
        # Generate a random 32-byte string
        MESSAGE_KEY = secrets.token_hex(32)

        # Update the parameter value in AWS Systems Manager Parameter Store
        response = ssm.put_parameter(
            Name='MESSAGE_KEY',
            Value=MESSAGE_KEY,
            Type='SecureString',
            Overwrite=True
        )

        return {
            'statusCode': 200,
            'body': 'MESSAGE_KEY parameter updated successfully.'
        }
    except Exception as e:
        print('Error updating MESSAGE_KEY parameter:', e)
        return {
            'statusCode': 500,
            'body': 'Error updating MESSAGE_KEY parameter.'
        }
  PYTHON
}
resource "aws_cloudwatch_event_rule" "lambda_trigger" {
  name        = "lambda_trigger_rule"
  description = "Rule to trigger Lambda function every 24 hours"

  schedule_expression = "rate(24 hours)"
}
resource "aws_cloudwatch_event_target" "lambda_target" {
  rule      = aws_cloudwatch_event_rule.lambda_trigger.name
  arn       = aws_lambda_function.Message_key_creator.arn
  target_id = "trigger-lambda-function"
}
resource "aws_cloudwatch_event_target" "lambda_target" {
  rule      = aws_cloudwatch_event_rule.lambda_trigger.name
  arn       = aws_lambda_function.JWT_TOKEN_CREATER.arn
  target_id = "trigger-lambda-function"
}

#------------------------------------------------------------------------------#
# Security groups
#------------------------------------------------------------------------------#

# The AWS provider removes the default "allow all "egress rule from all security
# groups, so it has to be defined explicitly.
resource "aws_security_group" "nodes" {
  name        = "${var.cluster_name}-nodes"
  description = "Allow all outgoing traffic to everywhere"
  vpc_id      = var.vpc_id
  tags        = local.tags
  egress {
    protocol    = -1
    from_port   = 0
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]
  }
    ingress {
    protocol    = -1
    from_port   = 0
    to_port     = 0
    self        = true
    description = "Allow incoming traffic from cluster nodes"

  }
  ingress {
    protocol    = -1
    from_port   = 0
    to_port     = 0
    cidr_blocks = var.pod_network_cidr_block != null ? [var.pod_network_cidr_block] : null
    description = "Allow incoming traffic from the Pods of the cluster"
  }
    ingress {
    protocol    = "tcp"
    from_port   = 22
    to_port     = 22
    cidr_blocks = var.allowed_ssh_cidr_blocks
  }
}


resource "aws_security_group" "Control-plane" {
  name        = "${var.cluster_name}-Control-plane"
  description = "Allow all outgoing traffic to everywhere"
  vpc_id      = var.vpc_id
  tags        = local.tags
  egress {
    protocol    = -1
    from_port   = 0
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]
  }
    ingress {
    protocol    = -1
    from_port   = 0
    to_port     = 0
    self        = true
    description = "Allow incoming traffic from cluster nodes"

  }
  ingress {
    protocol    = -1
    from_port   = 0
    to_port     = 0
    cidr_blocks = var.pod_network_cidr_block != null ? [var.pod_network_cidr_block] : null
    description = "Allow incoming traffic from the Pods of the cluster"
  }
    ingress {
    protocol    = "tcp"
    from_port   = 6443
    to_port     = 6443
    cidr_blocks = var.allowed_k8s_cidr_blocks
  }
    ingress {
    protocol    = "tcp"
    from_port   = 22
    to_port     = 22
    cidr_blocks = var.allowed_ssh_cidr_blocks
  }
}



#------------------------------------------------------------------------------#
# Elastic IP for master node
#------------------------------------------------------------------------------#

# EIP for master node because it must know its public IP during initialisation
resource "aws_eip" "master" {
  vpc  = true
  tags = local.tags
}

resource "aws_eip_association" "master" {
  allocation_id = aws_eip.master.id
  instance_id   = aws_instance.master.id
}

#------------------------------------------------------------------------------#
# Bootstrap token for kubeadm
#------------------------------------------------------------------------------#

# Generate bootstrap token
# See https://kubernetes.io/docs/reference/access-authn-authz/bootstrap-tokens/
resource "random_string" "token_id" {
  length  = 6
  special = false
  upper   = false
}

resource "random_string" "token_secret" {
  length  = 16
  special = false
  upper   = false
}

locals {
  token = "${random_string.token_id.result}.${random_string.token_secret.result}"
}

#------------------------------------------------------------------------------#
# EC2 instances
#------------------------------------------------------------------------------#



resource "aws_instance" "master" {
  ami           = var.ami_id
  iam_instance_profile = aws_iam_instance_profile.k8_profile
  instance_type = var.master_instance_type
  subnet_id     = var.subnet_id
  key_name      = aws_key_pair.main.key_name
  vpc_security_group_ids = [
    aws_security_group.Control-plane.id

  ]
  tags      = merge(local.tags, { "terraform-kubeadm:node" = "master" })
  

  # Saved in: /var/lib/cloud/instances/<instance-id>/user-data.txt [1]
  # Logs in:  /var/log/cloud-init-output.log [2]
  # [1] https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/user-data.html#user-data-shell-scripts
  # [2] https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/user-data.html#user-data-shell-scripts
  user_data = templatefile(
    "${path.module}/user-data.tftpl",
    {
      node              = "master",
      token             = local.token,
      cidr              = var.pod_network_cidr_block
      master_public_ip  = aws_eip.master.public_ip,
      master_private_ip = null,
      worker_index      = null
      argopass          = var.argo_pass
    }
  ) && templatefile(
    "${path.module}/credentials-script.tftpl",
    {
    }

  )
}

resource "aws_instance" "workers" {
  count                       = var.num_workers
  iam_instance_profile = aws_iam_instance_profile.k8_profile
  ami                         = var.ami_id
  instance_type               = var.worker_instance_type
  subnet_id                   = var.subnet_id
  associate_public_ip_address = true
  key_name                    = aws_key_pair.main.key_name
  vpc_security_group_ids = [
    aws_security_group.nodes.id

  ]
  tags      = merge(local.tags, { "terraform-kubeadm:node" = "worker-${count.index}" })

  user_data = templatefile(
    "${path.module}/user-data.tftpl",
    {
      node              = "worker",
      token             = local.token,
      cidr              = null,
      master_public_ip  = null,
      master_private_ip = aws_instance.master.private_ip,
      worker_index      = count.index
    }
  )
}


resource "aws_instance" "tool-chess" {
  ami                         = var.ami_id
  iam_instance_profile = aws_iam_instance_profile.k8_profile
  instance_type               = var.worker_instance_type
  subnet_id                   = var.subnet_id
  associate_public_ip_address = true
  key_name                    = aws_key_pair.main.key_name
  vpc_security_group_ids = [
    aws_security_group.nodes.id
  ]
  tags      = merge(local.tags, { "terraform-kubeadm:node" = "tool-chess" })
 
  user_data = templatefile(
    "${path.module}/user-data.tftpl",
    {
      node              = "tool-chess",
      token             = local.token,
      master_private_ip = aws_instance.master.private_ip
      
    }
  )
}

#------------------------------------------------------------------------------#
# Wait for bootstrap to finish on all nodes
#------------------------------------------------------------------------------#

resource "null_resource" "wait_for_bootstrap_to_finish" {
  provisioner "local-exec" {
    command = <<-EOF
    alias ssh='ssh -q -i ${var.private_key_file} -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null'
    while true; do
      sleep 2
      ! ssh ec2-user@${aws_eip.master.public_ip} [[ -f /home/ec2-user/done ]] >/dev/null && continue
      ! ssh ec2-user@${aws_instance.tool-chess.public_ip} [[ -f /home/ec2-user/done ]] >/dev/null && continue
      %{for worker_public_ip in aws_instance.workers[*].public_ip~}
      ! ssh ec2-user@${worker_public_ip} [[ -f /home/ec2-user/done ]] >/dev/null && continue
      %{endfor~}
      break
    done
    EOF
  }
  triggers = {
    instance_ids = join(",", concat([aws_instance.master.id], aws_instance.workers[*].id))
  }
}

#------------------------------------------------------------------------------#
# Download kubeconfig file from master node to local machine
#------------------------------------------------------------------------------#

resource "null_resource" "download_kubeconfig_file" {
  provisioner "local-exec" {
    command = <<-EOF
    alias scp='scp -q -i ${var.private_key_file} -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null'
    scp ec2-user@${aws_eip.master.public_ip}:/home/ec2-user/admin.conf ${var.kubeconfig != null ? var.kubeconfig : "${var.cluster_name}.conf"} >/dev/null
    EOF
  }
  triggers = {
    wait_for_bootstrap_to_finish = null_resource.wait_for_bootstrap_to_finish.id
  }
}

