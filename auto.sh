#!/bin/bash

# Enable error handling and logging
set -e
exec 1> >(logger -s -t $(basename $0)) 2>&1

# Function to get public IP
get_public_ip() {
    for i in {1..5}; do
        PUBLIC_IP=$(curl -s ifconfig.me)
        if [[ ! -z "$PUBLIC_IP" ]]; then
            echo "$PUBLIC_IP"
            return 0
        fi
        echo "Attempt $i: Waiting for public IP..."
        sleep 5
    done
    return 1
}

# Update & Install Dependencies
echo "Updating system and installing dependencies..."
sudo apt update -y
sudo apt install -y docker.io docker-compose curl
sudo docker --version
sudo docker-compose --version

# Start Docker Service
echo "Starting Docker service..."
sudo systemctl start docker
sudo systemctl enable docker

# Allow Docker without sudo
sudo usermod -aG docker ubuntu

# Create app folder
mkdir -p ~/app && cd ~/app

# Wait for Docker to be fully ready
echo "Waiting for Docker to be ready..."
for i in {1..30}; do
    if sudo docker info > /dev/null 2>&1; then
        echo "Docker is ready!"
        break
    fi
    echo "Waiting for Docker to start... ($i/30)"
    sleep 2
done

# Get public IP with retry
echo "Getting public IP..."
PUBLIC_IP=$(get_public_ip)
if [[ -z "$PUBLIC_IP" ]]; then
    echo "Failed to get public IP"
    exit 1
fi
echo "Public IP is: $PUBLIC_IP"

# Create Docker Compose File
echo "Creating docker-compose.yml..."
sudo cat <<EOF > docker-compose.yml
version: "3.8"

services:
  backend:
    image: kiritahir/hello-devops-backend:latest
    container_name: backend-container
    ports:
      - "8000:8000"
    restart: always
    networks:
      - app-network

  frontend:
    image: kiritahir/hello-devops-frontend:latest
    container_name: frontend-container
    environment:
      - VITE_BACKEND_URL=http://$PUBLIC_IP:8000
    ports:
      - "80:80"
    depends_on:
      - backend
    restart: always
    networks:
      - app-network

networks:
  app-network:
    driver: bridge
EOF

# Pull images first
echo "Pulling Docker images..."
sudo docker-compose pull

# Run Docker Compose
echo "Starting containers..."
sudo docker-compose up -d

# Verify containers are running
echo "Verifying containers..."
sleep 10
if sudo docker ps | grep -q 'backend-container' && sudo docker ps | grep -q 'frontend-container'; then
    echo "Containers are running successfully!"
    echo "Frontend URL: http://$PUBLIC_IP"
    echo "Backend URL: http://$PUBLIC_IP:8000"
else
    echo "Container verification failed!"
    sudo docker ps
    sudo docker-compose logs
fi

echo "Setup complete!"
