#!/bin/bash

set -e  # Exit on any error

# Check if AWS CLI is installed
if ! command -v aws &>/dev/null; then
    echo "Installing AWS CLI..."
    curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
    unzip awscliv2.zip
    sudo ./aws/install
    rm -rf awscliv2.zip aws/
    echo "AWS CLI installed successfully."
else
    echo "AWS CLI is already installed."
fi

aws --version

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

echo "AWS CLI is properly configured."

# Prompt user for AWS region
default_region="us-west-2"
read -p "Enter the AWS region to deploy the EKS cluster (default: $default_region): " aws_region
aws_region=${aws_region:-$default_region}

# Prompt user for cluster name
default_cluster_name="trendpocalypse"
read -p "Enter the name for the EKS cluster (default: $default_cluster_name): " cluster_name
cluster_name=${cluster_name:-$default_cluster_name}

echo "Fetching available SSH key pairs in region $aws_region..."

# List all AWS EC2 key pairs in the selected region
key_pairs=$(aws ec2 describe-key-pairs --region $aws_region --query 'KeyPairs[*].KeyName' --output text)

if [ -z "$key_pairs" ]; then
    echo "No SSH key pairs found in region $aws_region. You need to create one before proceeding."
    echo "Use 'aws ec2 create-key-pair --key-name <key-name> --region $aws_region' to create a key."
    exit 1
fi

echo "Available SSH Key Pairs:"
select ssh_key in $key_pairs "Enter a custom key"; do
    if [ "$ssh_key" == "Enter a custom key" ]; then
        read -p "Enter your custom SSH key name: " ssh_key
    fi
    if [ -n "$ssh_key" ]; then
        break
    fi
done

echo "Selected SSH key: $ssh_key"

echo "Creating EKS cluster: $cluster_name in region $aws_region..."

# Create EKS cluster with selected SSH key
eksctl create cluster \
    --region $aws_region \
    --tags Project=$cluster_name \
    --tags owner=Player \
    --tags autostop=no \
    --name $cluster_name \
    --node-type t3a.large \
    --node-volume-size 50 \
    --full-ecr-access \
    --alb-ingress-access \
    --ssh-access \
    --ssh-public-key $ssh_key

echo "EKS cluster $cluster_name has been successfully created."

# Deploy the containerized application
echo "Deploying the container image to EKS..."

# Create a Kubernetes deployment YAML file
cat <<EOF > deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: webapp08
  labels:
    app: webapp08
spec:
  replicas: 1
  selector:
    matchLabels:
      app: webapp08
  template:
    metadata:
      labels:
        app: webapp08
    spec:
      containers:
      - name: webapp08
        image: fafiorim/webapp08:latest
        ports:
        - containerPort: 80
EOF

# Apply the deployment to the cluster
kubectl apply -f deployment.yaml

# Expose the deployment as a service
kubectl expose deployment webapp08 --type=LoadBalancer --name=webapp08-service --port=80 --target-port=80

echo "Application has been deployed successfully. You can check the service with:"
echo "kubectl get services webapp08-service"
