#!/bin/bash

set -e  # Exit on any error

# Check if eksctl is installed
if ! command -v eksctl &>/dev/null; then
    echo "Installing eksctl..."
    ARCH=amd64  # Change this if running on ARM system
    PLATFORM=$(uname -s)_$ARCH
    curl -sLO "https://github.com/eksctl-io/eksctl/releases/latest/download/eksctl_$PLATFORM.tar.gz"
    
    # (Optional) Verify checksum
    curl -sL "https://github.com/eksctl-io/eksctl/releases/latest/download/eksctl_checksums.txt" | grep $PLATFORM | sha256sum --check
    
    tar -xzf eksctl_$PLATFORM.tar.gz -C /tmp && rm eksctl_$PLATFORM.tar.gz
    sudo mv /tmp/eksctl /usr/local/bin
    echo "eksctl installed successfully."
else
    echo "eksctl is already installed."
fi

eksctl version

# Check if kubectl is installed
if ! command -v kubectl &>/dev/null; then
    echo "Installing kubectl..."
    curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
    sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
    chmod +x kubectl
    mkdir -p ~/.local/bin
    mv ./kubectl ~/.local/bin/kubectl
    echo "kubectl installed successfully."
else
    echo "kubectl is already installed."
fi

kubectl version --client

# Check AWS configuration
if ! aws sts get-caller-identity &>/dev/null; then
    echo "AWS CLI is not properly configured. Please run 'aws configure' first."
    exit 1
fi

echo "AWS CLI is properly configured. Proceeding with EKS cluster creation."

# Prompt user for cluster name
default_cluster_name="trendpocalypse"
read -p "Enter the name for the EKS cluster (default: $default_cluster_name): " cluster_name
cluster_name=${cluster_name:-$default_cluster_name}

echo "Creating EKS cluster: $cluster_name"

# Create EKS cluster
eksctl create cluster \
    --tags Project=$cluster_name \
    --tags owner=Player \
    --tags autostop=no \
    --name $cluster_name \
    --node-type t3a.large \
    --node-volume-size 50 \
    --full-ecr-access \
    --alb-ingress-access \
    --ssh-access

echo "EKS cluster $cluster_name has been successfully created."
