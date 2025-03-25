#!/bin/bash

# Enable error handling and logging
set -e
exec 1> >(logger -s -t $(basename $0)) 2>&1

# Function to get public IP with retries
get_public_ip() {
    local max_retries=5
    local retry_count=0
    local wait_time=5

    while [ $retry_count -lt $max_retries ]; do
        PUBLIC_IP=$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4 || curl -s https://api.ipify.org)
        if [ ! -z "$PUBLIC_IP" ]; then
            echo "$PUBLIC_IP"
            return 0
        fi
        retry_count=$((retry_count + 1))
        echo "Failed to get public IP. Retrying in $wait_time seconds... (Attempt $retry_count/$max_retries)"
        sleep $wait_time
    done
    echo "Failed to get public IP after $max_retries attempts"
    return 1
}

# Update system and install dependencies
apt-get update
apt-get install -y docker.io docker-compose curl

# Start Docker service
systemctl start docker
systemctl enable docker

# Allow ubuntu user to run docker commands without sudo
usermod -aG docker ubuntu

# Create application directory
mkdir -p /app
cd /app

# Wait for Docker to be ready
while ! docker info > /dev/null 2>&1; do
    echo "Waiting for Docker to be ready..."
    sleep 5
done

# Get public IP
PUBLIC_IP=$(get_public_ip)
if [ $? -ne 0 ]; then
    echo "Failed to get public IP. Exiting."
    exit 1
fi

echo "Public IP: $PUBLIC_IP"

# Create docker-compose.yml
cat > docker-compose.yml <<EOL
version: '3'
services:
  backend:
    container_name: backend-container
    image: jaydanid/backend:latest
    ports:
      - "8000:8000"
    environment:
      - HOST=0.0.0.0
      - PORT=8000
    restart: always

  frontend:
    container_name: frontend-container
    image: jaydanid/frontend:latest
    ports:
      - "80:80"
    environment:
      - VITE_BACKEND_URL=http://${PUBLIC_IP}:8000
    depends_on:
      - backend
    restart: always
EOL

# Stop and remove existing containers and volumes
docker-compose down -v || true

# Pull latest images
docker-compose pull

# Start services
docker-compose up -d

# Verify environment variables
echo "Verifying environment variables..."
docker exec frontend-container env | grep VITE_BACKEND_URL
docker exec backend-container env | grep PORT

# Wait for services to be ready
echo "Waiting for services to be ready..."
timeout 60s bash -c 'until curl -s http://localhost:8000/start-deployment > /dev/null; do sleep 5; done'
timeout 60s bash -c 'until curl -s http://localhost > /dev/null; do sleep 5; done'

echo "Deployment completed successfully!"
echo "Frontend URL: http://${PUBLIC_IP}"
echo "Backend URL: http://${PUBLIC_IP}:8000"
