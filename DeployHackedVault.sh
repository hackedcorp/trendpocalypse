#!/bin/bash
# step2.sh

# Prompting the user for the GitHub repository URL
while true; do
  read -p "Enter the GitHub repository URL you want to clone: " repo_url
  if [[ "$repo_url" == "https://github.com/hackedcorp/hackedvault" ]]; then
    echo "The repository https://github.com/hackedcorp/hackedvault is not allowed. Please provide a different URL."
  elif [[ -n "$repo_url" ]]; then
    echo "Cloning the repository from $repo_url..."
    git clone "$repo_url"
    if [[ $? -eq 0 ]]; then
      echo "Repository cloned successfully."
      break
    else
      echo "Failed to clone the repository. Please check the URL and try again."
    fi
  else
    echo "No URL provided. Please enter a valid GitHub repository URL."
  fi
done

# Navigate into the cloned directory
repo_name=$(basename "$repo_url" .git)
cd "$repo_name" || { echo "Failed to enter repo directory"; exit 1; }

# Check if Dockerfile exists
if [[ ! -f "Dockerfile" ]]; then
  echo "ERROR: Dockerfile not found in the repository. Please ensure it exists."
  exit 1
fi

# Prompt user for Vision One API Key (input will be hidden)
while [[ -z "$FSS_API_KEY" ]]; do
  read -s -p "Enter your Vision One API Key: " FSS_API_KEY
  echo ""
  if [[ -z "$FSS_API_KEY" ]]; then
    echo "⚠️ API Key cannot be empty. Please enter a valid key."
  fi
done

# Stop and remove existing container (only if it exists)
docker ps -q --filter "name=hackedvault" | grep -q . && docker stop hackedvault
docker ps -a -q --filter "name=hackedvault" | grep -q . && docker rm hackedvault

# Build the Docker image
docker build -t hackedvault:latest .

# Run the container with the correct image name and API Key
docker run -d \
  -p 3000:3000 -p 3443:3443 -p 3001:3001 \
  -e FSS_API_ENDPOINT="antimalware.us-1.cloudone.trendmicro.com:443" \
  -e FSS_API_KEY="$FSS_API_KEY" \
  -e USER_USERNAME="user" \
  -e USER_PASSWORD="sdePgqEr4#4tSlvg" \
  -e FSS_CUSTOM_TAGS="env:bytevault,team:security" \
  -e SECURITY_MODE="disabled" \
  --name hackedvault \
  hackedvault:latest

# Check if Docker run was successful
if [[ $? -eq 0 ]]; then
  # Getting the local IP address of the server
  local_ip=$(hostname -I | awk '{print $1}')

  # Printing the URL to access the app
  if [[ -n "$local_ip" ]]; then
    echo "✅ Your application is running and can be accessed at: http://$local_ip:3000/ or https://$local_ip:3443/"
  else
    echo "⚠️ Failed to retrieve the local IP address. Please check your network settings."
  fi
else
  echo "❌ Failed to start the Docker container. Please check for errors and try again."
fi
