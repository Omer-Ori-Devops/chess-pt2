provider "aws" {
  region  = "eu-central-1"
  access_key = "enterhere"
  secret_key = "enter here"
}

resource "aws_s3_bucket" "chess-ops" {
  bucket = "chess-ops"
  
}


terraform {
  required_version = ">= 0.12"
  backend "s3" {
    bucket = aws_s3_bucket.chess-ops.id
    key    = "terraform.tfstate"
    region = "eu-central-1"
  }
}

module "kubeadm-bootstrap" {
    BUCKET = aws_s3_bucket.chess-ops.id
    source = "./kubeadm-bootstrap"
    vpc_id = "vpc id"
    cluster_name = "chess-ops"
    master_instance_type = "t2.medium"
    num_workers = 2
    worker_instance_type = "t2.medium"
    ami_id = "id of ami"
    private_key_file = "location of private key"
    public_key_file = "location of public key"
    kubeconfig = "kubeconfig.conf"
    argo_pass = "argocd password"
}

