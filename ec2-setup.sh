#!/bin/bash
# EC2 서버 초기 설정 스크립트 (한번만 실행)
# Usage: ssh ubuntu@your-server 'bash -s' < ec2-setup.sh

echo "🚀 Setting up EC2 server for Blue-Green deployment..."

# System update
echo "📦 Updating system packages..."
sudo apt update && sudo apt upgrade -y

# Install Docker
echo "🐳 Installing Docker..."
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh
sudo usermod -aG docker ubuntu
sudo systemctl start docker
sudo systemctl enable docker

# Install Docker Compose
echo "🔧 Installing Docker Compose..."
sudo curl -L "https://github.com/docker/compose/releases/download/v2.24.0/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
sudo chmod +x /usr/local/bin/docker-compose
sudo ln -sf /usr/local/bin/docker-compose /usr/bin/docker-compose

# Install additional tools
echo "🛠️ Installing additional tools..."
sudo apt install -y curl wget git nginx

# Create deployment directory
echo "📁 Creating deployment directory..."
mkdir -p ~/bgTest/v5ToWindow

# Verify installations
echo "✅ Verification:"
docker --version
docker-compose --version
nginx -v

echo "🎉 EC2 server setup completed!"
echo "📋 Next steps:"
echo "1. Log out and log back in to activate Docker group permissions"
echo "2. Run your GitLab CI/CD pipeline"