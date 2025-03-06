#!/bin/bash
# step3.sh

# Check if kubectl is installed
# Check if kubectl is installed, if not install it
if ! command -v kubectl &> /dev/null; then
  echo "⚠️ kubectl is not installed. Installing now..."
  curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
  sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
  chmod +x kubectl
  mkdir -p ~/.local/bin
  mv ./kubectl ~/.local/bin/kubectl
  echo "✅ kubectl has been installed."
fi

# Display installed kubectl version
kubectl version --client

# Prompt the user for inputs
read -p "Enter AWS Region (default: us-west-2): " AWS_REGION
AWS_REGION=${AWS_REGION:-us-west-2}

read -p "Enter the EKS Cluster Name (default: hackedvault-cluster): " EKS_CLUSTER
EKS_CLUSTER=${EKS_CLUSTER:-hackedvault-cluster}

read -p "Enter the Docker Image Name (default: hackedvault): " DOCKER_IMAGE_NAME
DOCKER_IMAGE_NAME=${DOCKER_IMAGE_NAME:-hackedvault}

read -p "Enter the Docker Image Tag (default: latest): " IMAGE_TAG
IMAGE_TAG=${IMAGE_TAG:-latest}

read -p "Enter the Kubernetes manifests directory (default: k8s): " K8S_DIR
K8S_DIR=${K8S_DIR:-k8s}

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

# Check if the Docker image exists locally
if docker image inspect ${DOCKER_IMAGE_NAME}:${IMAGE_TAG} &>/dev/null; then
  echo "✅ Local Docker image found: ${DOCKER_IMAGE_NAME}:${IMAGE_TAG}"
else
  echo "❌ Local Docker image not found. Building the image..."
  if [[ ! -f "Dockerfile" ]]; then
    echo "❌ ERROR: Dockerfile not found. Make sure you are running the script from the correct directory."
    exit 1
  fi
  docker build -t ${DOCKER_IMAGE_NAME}:${IMAGE_TAG} .
fi

# Tag and push the existing local image to ECR
echo "Pushing image to ECR..."
docker tag ${DOCKER_IMAGE_NAME}:${IMAGE_TAG} ${ECR_URI}
docker push ${ECR_URI}

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
