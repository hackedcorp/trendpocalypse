#!/bin/bash
# cleanup.sh

echo "🚀 Starting cleanup for both Kubernetes (EKS) and local Docker..."

# Prompt user for cleanup target
read -p "Do you want to clean up (1) Kubernetes (EKS), (2) Local Docker, or (3) Both? [1/2/3]: " CLEANUP_OPTION

# Common function to ask for confirmation before deleting critical resources
confirm_action() {
    read -p "⚠️ Are you sure you want to proceed with this cleanup? This action is irreversible. (y/N): " CONFIRM
    if [[ "$CONFIRM" != "y" && "$CONFIRM" != "Y" ]]; then
        echo "❌ Cleanup aborted."
        exit 0
    fi
}

### **KUBERNETES (EKS) CLEANUP**
if [[ "$CLEANUP_OPTION" == "1" || "$CLEANUP_OPTION" == "3" ]]; then
    echo "🛠 Cleaning up Kubernetes resources..."

    # Prompt for AWS and Kubernetes details
    read -p "Enter AWS Region (default: us-east-1): " AWS_REGION
    AWS_REGION=${AWS_REGION:-us-east-1}

    read -p "Enter the EKS Cluster Name (default: trendpocalypse): " EKS_CLUSTER
    EKS_CLUSTER=${EKS_CLUSTER:-trendpocalypse}

    read -p "Enter the Docker Image Name (default: hackedvault): " DOCKER_IMAGE_NAME
    DOCKER_IMAGE_NAME=${DOCKER_IMAGE_NAME:-hackedvault}

    read -p "Enter the Docker Image Tag (default: latest): " IMAGE_TAG
    IMAGE_TAG=${IMAGE_TAG:-latest}

    # Get AWS Account ID
    ACCOUNT_ID=$(aws sts get-caller-identity --query "Account" --output text)
    ECR_URI="${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${DOCKER_IMAGE_NAME}:${IMAGE_TAG}"

    confirm_action

    echo "⏳ Deleting Kubernetes resources..."
    kubectl delete deployment hackedvault --ignore-not-found
    kubectl delete svc hackedvault-service --ignore-not-found
    kubectl delete configmap hackedvault-config --ignore-not-found
    kubectl delete secret hackedvault-secrets --ignore-not-found
    sleep 5

    echo "✅ Kubernetes resources removed."

    # Check if the image exists in ECR
    IMAGE_EXISTS=$(aws ecr list-images --repository-name ${DOCKER_IMAGE_NAME} --region ${AWS_REGION} --query "imageIds[?imageTag=='${IMAGE_TAG}']" --output text)

    if [[ -n "$IMAGE_EXISTS" ]]; then
        echo "⏳ Removing Docker image from ECR..."
        aws ecr batch-delete-image --repository-name ${DOCKER_IMAGE_NAME} --region ${AWS_REGION} --image-ids imageTag=${IMAGE_TAG}
        echo "✅ Docker image removed from ECR."
    else
        echo "⚠️ No image found in ECR with tag '${IMAGE_TAG}'. Skipping ECR cleanup."
    fi

    # Check if the ECR repository exists before attempting to delete it
    ECR_REPO_EXISTS=$(aws ecr describe-repositories --repository-names ${DOCKER_IMAGE_NAME} --region ${AWS_REGION} --query "repositories[0].repositoryName" --output text 2>/dev/null)

    if [[ "$ECR_REPO_EXISTS" == "$DOCKER_IMAGE_NAME" ]]; then
        echo "⏳ Deleting ECR repository..."
        aws ecr delete-repository --repository-name ${DOCKER_IMAGE_NAME} --region ${AWS_REGION} --force
        echo "✅ ECR repository deleted."
    else
        echo "⚠️ ECR repository '${DOCKER_IMAGE_NAME}' does not exist. Skipping."
    fi
fi

### **LOCAL DOCKER CLEANUP**
if [[ "$CLEANUP_OPTION" == "2" || "$CLEANUP_OPTION" == "3" ]]; then
    echo "🛠 Cleaning up Local Docker resources..."
    confirm_action

    echo "⏳ Stopping all running Docker containers..."
    docker ps -q | xargs -r docker stop

    echo "🗑️ Removing all Docker containers..."
    docker ps -aq | xargs -r docker rm

    echo "🗑️ Removing all Docker services (if using Docker Swarm)..."
    docker service ls -q | xargs -r docker service rm

    echo "🗑️ Removing all Docker deployments (if using Docker Swarm)..."
    docker stack ls | awk '{if(NR>1) print $1}' | xargs -r docker stack rm

    echo "🗑️ Removing all Docker images..."
    docker images -q | xargs -r docker rmi -f

    echo "🗑️ Removing all unused Docker volumes..."
    docker volume prune -f

    echo "🗑️ Removing all unused Docker networks..."
    docker network prune -f

    echo "🛑 Resetting Docker system (removes build cache)..."
    docker system prune -a -f

    echo "✅ Local Docker cleanup complete!"
fi

echo "🎉 Cleanup process finished successfully!"
