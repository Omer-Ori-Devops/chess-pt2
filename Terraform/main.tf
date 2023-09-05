provider "aws" {
  region  = "eu-central-1"
}


terraform {
  required_providers{
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }

  }
  required_version = ">= 0.12"
  backend "s3" {
    bucket = "chess-ops"
    key    = "terraform.tfstate"
    region = "eu-central-1"
  }
}



module "kubeadm-bootstrap" {
    BUCKET = "chess-op"
    source = "./kubeadm-bootstrap"
    vpc_id = "vpc id"
    cluster_name = "chess-ops"
    master_instance_type = "t2.medium"
    num_workers = 2
    worker_instance_type = "t2.medium"
    ami_id = "ami-0dc7fe3dd38437495" #centos aws linux ami id
    #private_key_file = "location of private key"
    #public_key_file = "location of public key"
    #kubeconfig = "kubeconfig.conf"
}

