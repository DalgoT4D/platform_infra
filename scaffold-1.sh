#!/bin/sh

# OS updates
# Package installation

ROOT_PEMFILE="secrets/ddp-airbyte.pem"
MACHINE_IP=`cat machineip.txt`

if [ "x${MACHINE_IP}" == "x" ]; then
  echo "Please set MACHINE_IP before running this script"
  exit 1
fi

echo "Updating packages..."
ssh -i ${ROOT_PEMFILE} ubuntu@${MACHINE_IP} sudo apt update
ssh -i ${ROOT_PEMFILE} ubuntu@${MACHINE_IP} sudo apt upgrade -y

echo "Installing docker"
ssh -i ${ROOT_PEMFILE} ubuntu@${MACHINE_IP} sudo apt install docker.io -y
ssh -i ${ROOT_PEMFILE} ubuntu@${MACHINE_IP} sudo curl -L "https://github.com/docker/compose/releases/download/v2.2.3/docker-compose-Linux-x86_64" -o /usr/local/bin/docker-compose
# ssh -i ${ROOT_PEMFILE} ubuntu@${MACHINE_IP} sudo snap install docker
ssh -i ${ROOT_PEMFILE} ubuntu@${MACHINE_IP} sudo chmod +x /usr/local/bin/docker-compose 
ssh -i ${ROOT_PEMFILE} ubuntu@${MACHINE_IP} sudo apt install unzip -y 

echo "Installing venv for python 3.10"
ssh -i ${ROOT_PEMFILE} ubuntu@${MACHINE_IP} "sudo apt install python3.10-venv -y"
ssh -i ${ROOT_PEMFILE} ubuntu@${MACHINE_IP} "sudo apt install pip -y"

echo "Installing AWS CLI"
ssh -i ${ROOT_PEMFILE} ubuntu@${MACHINE_IP} curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
ssh -i ${ROOT_PEMFILE} ubuntu@${MACHINE_IP} unzip awscliv2.zip
ssh -i ${ROOT_PEMFILE} ubuntu@${MACHINE_IP} sudo ./aws/install

echo "Restarting machine"
ssh -i ${ROOT_PEMFILE} ubuntu@${MACHINE_IP} sudo reboot

