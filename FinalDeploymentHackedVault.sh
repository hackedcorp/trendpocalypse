#!/bin/bash
# step3.sh

# Function to check if a Git repository exists in the current directory or subdirectories
check_git_repo() {
  if find . -type d -name ".git" | grep -q .; then
    return 0  # Git repo found
  else
    return 1  # No Git repo found
  fi
}

# Ensure there is a cloned repository before proceeding
if ! check_git_repo; then
  echo "⚠️ No Git repository found in the current directory or subdirectories."
  while true; do
    read -p "Enter the GitHub repository URL you want to clone: " repo_url
    if [[ "$repo_url" == "https://github.com/hackedcorp/hackedvault" ]]; then
      echo "🚫 The repository https://github.com/hackedcorp/hackedvault is not allowed. Please provide a different URL."
    elif [[ -n "$repo_url" ]]; then
      echo "Cloning the repository from $repo_url..."
      git clone "$repo_url"
      if [[ $? -eq 0 ]]; then
        echo "✅ Repository cloned successfully."
        break
      else
        echo "❌ Failed to clone the repository. Please check the URL and try again."
      fi
    else
      echo "⚠️ No URL provided. Please enter a valid GitHub repository URL."
    fi
  done
fi

# Check if kubectl is installed, if not inform the user
echo "Checking if kubectl is installed..."
if ! command -v kubectl &> /dev/null; then
  echo "⚠️ kubectl is not installed. Go install it and then return to this step: https://kubernetes.io/docs/tasks/tools/install-kubectl-linux/"
  exit 1
fi

# Display installed kubectl version
kubectl version --client

# Prompt the user for inputs
read -p "Enter AWS Region (default: us-east-1): " AWS_REGION
AWS_REGION=${AWS_REGION:-us-east-1}

read -p "Enter the EKS Cluster Name (default: trendpocalypse): " EKS_CLUSTER
EKS_CLUSTER=${EKS_CLUSTER:-trendpocalypse}

read -p "Enter the Docker Image Name (default: hackedvault): " DOCKER_IMAGE_NAME
DOCKER_IMAGE_NAME=${DOCKER_IMAGE_NAME:-hackedvault}

read -p "Enter the Docker Image Tag (default: latest): " IMAGE_TAG
IMAGE_TAG=${IMAGE_TAG:-latest}

read -p "Enter the Kubernetes manifests directory (default: hackedvault/k8s): " K8S_DIR
K8S_DIR=${K8S_DIR:-hackedvault/k8s}

# Prompt user for Vision One API Key (input will be hidden)
while [[ -z "$FSS_API_KEY" ]]; do
  read -s -p "Enter your Vision One API Key: " FSS_API_KEY
  echo ""
  if [[ -z "$FSS_API_KEY" ]]; then
    echo "⚠️ API Key cannot be empty. Please enter a valid key."
  fi
done

# Get AWS Account ID
ACCOUNT_ID=$(aws sts get-caller-identity --query "Account" --output text)
ECR_URI="${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${DOCKER_IMAGE_NAME}:${IMAGE_TAG}"

# Ensure AWS CLI and kubectl are configured for EKS
echo "Configuring kubectl for the EKS cluster..."
aws eks update-kubeconfig --region ${AWS_REGION} --name ${EKS_CLUSTER}

# Check if ECR repository exists, create if not
if ! aws ecr describe-repositories --repository-names "${DOCKER_IMAGE_NAME}" &>/dev/null; then
    echo "Creating ECR repository: ${DOCKER_IMAGE_NAME}"
    aws ecr create-repository --repository-name "${DOCKER_IMAGE_NAME}"
fi

# Authenticate Docker with AWS ECR
echo "Logging into Amazon ECR..."
aws ecr get-login-password --region ${AWS_REGION} | docker login --username AWS --password-stdin ${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com

# Check if the Dockerfile exists in a subdirectory
echo "Searching for Dockerfile..."
DOCKERFILE_PATH=$(find . -name Dockerfile | head -n 1)
if [[ -z "$DOCKERFILE_PATH" ]]; then
  echo "❌ ERROR: Dockerfile not found in any subdirectory."
  exit 1
fi

BUILD_CONTEXT=$(dirname "$DOCKERFILE_PATH")
echo "🛠️  Found Dockerfile in: $BUILD_CONTEXT"

# Build the Docker image using the correct context
docker build -t ${DOCKER_IMAGE_NAME}:${IMAGE_TAG} "$BUILD_CONTEXT"

# Tag and push the existing local image to ECR
echo "Pushing image to ECR..."
docker tag ${DOCKER_IMAGE_NAME}:${IMAGE_TAG} ${ECR_URI}
docker push ${ECR_URI}

# Ask if the user wants to scan the container with TMAS
read -p "Do you want to scan the container with TMAS? (y/N): " SCAN_TMAS
SCAN_TMAS=${SCAN_TMAS,,} # Convert to lowercase (y/n)

if [[ "$SCAN_TMAS" == "y" ]]; then
  # Check if TMAS is installed
  if ! command -v tmas &> /dev/null; then
    echo "⚠️ TMAS is not installed. Please install TMAS before scanning."
    exit 1
  fi
  
  # Check if TMAS_API_KEY is set
  if [[ -z "$TMAS_API_KEY" ]]; then
    echo "⚠️ TMAS_API_KEY is not set. Please export your API key (e.g., export TMAS_API_KEY=<your api key>)"
    exit 1
  fi
  
  # Scan the container image
  echo "🔍 Scanning image with TMAS: $ECR_URI"
  tmas scan -SVM registry:${ECR_URI} 2>&1
fi

# Delete existing deployment if it exists
if kubectl get deployment hackedvault &>/dev/null; then
    echo "⚠️ Existing deployment found. Deleting..."
    kubectl delete deployment hackedvault
    kubectl delete svc hackedvault-service
    sleep 10  # Wait for cleanup
fi

# Set up Kubernetes manifest directory
mkdir -p ${K8S_DIR}

# Create Kubernetes manifests dynamically
echo "Creating Kubernetes manifests..."

# Deployment YAML with HTTPS support
cat <<EOF > ${K8S_DIR}/deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: hackedvault
  labels:
    app: hackedvault
spec:
  replicas: 1
  selector:
    matchLabels:
      app: hackedvault
  template:
    metadata:
      labels:
        app: hackedvault
    spec:
      containers:
      - name: hackedvault
        image: ${ECR_URI}
        imagePullPolicy: Always
        ports:
        - containerPort: 3000
        - containerPort: 3443
        envFrom:
        - configMapRef:
            name: hackedvault-config
        - secretRef:
            name: hackedvault-secrets
EOF

# Fixed Service YAML with named ports for HTTPS support
cat <<EOF > ${K8S_DIR}/service.yaml
apiVersion: v1
kind: Service
metadata:
  name: hackedvault-service
spec:
  selector:
    app: hackedvault
  ports:
    - name: http
      protocol: TCP
      port: 80
      targetPort: 3000
    - name: https
      protocol: TCP
      port: 443
      targetPort: 3443
  type: LoadBalancer
EOF

# ConfigMap & Secrets YAML (Now includes API Key)
cat <<EOF > ${K8S_DIR}/config.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: hackedvault-config
data:
  FSS_API_ENDPOINT: "antimalware.us-1.cloudone.trendmicro.com:443"
  SECURITY_MODE: "logOnly"
  HTTP_PORT: "3000"
  HTTPS_PORT: "3443"

---
apiVersion: v1
kind: Secret
metadata:
  name: hackedvault-secrets
type: Opaque
data:
  USER_USERNAME: "$(echo -n "user" | base64 --wrap=0)"
  USER_PASSWORD: "$(echo -n "sdePgqEr4#4tSlvg" | base64 --wrap=0)"
  FSS_API_KEY: "$(echo -n "$FSS_API_KEY" | base64 --wrap=0)"  # Securely store the API Key
EOF

# Apply Kubernetes manifests
echo "Deploying application to EKS..."
kubectl apply -f ${K8S_DIR}/

# Wait for the LoadBalancer to get an external IP
echo "Waiting for LoadBalancer IP (this may take up to 5 minutes)..."
EXTERNAL_IP=""
while [ -z "$EXTERNAL_IP" ]; do
    sleep 10
    EXTERNAL_IP=$(kubectl get svc hackedvault-service --output=jsonpath='{.status.loadBalancer.ingress[0].hostname}')
    if [[ "$EXTERNAL_IP" == "<none>" || -z "$EXTERNAL_IP" ]]; then
        echo "Still waiting for the DNS to propagate..."
        EXTERNAL_IP=""
    fi
done

# Print the URL to access the app
echo "✅ Deployment successful! Access your app at:"
#echo "🌍 HTTP:  http://${EXTERNAL_IP}:80"
echo "🌍 HTTPS: https://${EXTERNAL_IP}:443"

echo ""
echo "🔍 If the hostname is not resolving, please wait a few minutes for AWS to propagate the DNS."
echo "📌 To check if your pods are running, use:"
echo "    kubectl get pods"
echo "📌 To check your Load Balancer, use:"
echo "    aws elb describe-load-balancers --region ${AWS_REGION} --query 'LoadBalancerDescriptions[*].[DNSName]' --output text"
