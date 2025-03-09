#!/bin/bash

# Installing essential packages
sudo apt-get update
sudo apt-get install -y apt-transport-https ca-certificates curl software-properties-common vim unzip iputils-ping jq

# Downloading docker install script
wget https://get.docker.com/ -O install_docker.sh

# Adding execute permission to the script
chmod +x install_docker.sh

# Running the script
sudo ./install_docker.sh

# Adding user to docker group
sudo usermod -aG docker $(whoami)

# Checking if Docker was installed successfully
if docker --version >/dev/null 2>&1; then
    # Ensuring the directory exists
    sudo mkdir -p /home/ubuntu/scripts
    
    # Creating a flag file
    echo "CTF{docker_setup_success}" | sudo tee /home/ubuntu/scripts/flag.txt > /dev/null
    echo "Docker installation successful. Flag file created at /home/ubuntu/scripts/flag.txt"
else
    echo "Docker installation failed. Flag file will not be created."
fi

# Completion message
echo "Setup complete! Please log out and back in to apply Docker group changes."
