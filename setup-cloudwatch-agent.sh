#!/bin/sh

ROOT_PEMFILE="secrets/ddp-airbyte.pem"
MACHINE_IP=`cat machineip.txt`

if [ "x${MACHINE_IP}" == "x" ]; then
  echo "Please set MACHINE_IP before running this script"
  exit 1
fi

echo "Installing Cloudwatch Agent"
downloadlink="https://s3.ap-south-1.amazonaws.com/amazoncloudwatch-agent-ap-south-1/ubuntu/amd64/latest/amazon-cloudwatch-agent.deb"
ssh -i ${ROOT_PEMFILE} ubuntu@${MACHINE_IP} wget ${downloadlink}
ssh -i ${ROOT_PEMFILE} ubuntu@${MACHINE_IP} sudo dpkg -i -E ./amazon-cloudwatch-agent.deb

echo "Starting Cloudwatch Agent"
ssh -i ${ROOT_PEMFILE} ubuntu@${MACHINE_IP} sudo /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -a fetch-config -m ec2 -s

