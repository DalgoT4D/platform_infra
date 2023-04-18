#!/bin/sh

# Creates a user account and sets up SSH keys for login

ROOT_PEMFILE="ddp-airbyte.pem"
MACHINE_IP=`cat machineip.txt`

if [ "x${MACHINE_IP}" == "x" ]; then
  echo "Please set MACHINE_IP before running this script"
  exit 1
fi

# change the user for different branches / experiments
if [ "x${DDPUSER}" == "x" ]; then
  DDPUSER="ddp"
fi

# run ssh-keygen on local machine for development builds
# for production we need a stronger guarantee that we won't be locked out, so we re-use a known key pair
if [ "x${PROD}" == "x" ]; then
  DDP_PUBLICKEYFILE="${DDPUSER}.pub"
  DDP_PRIVATEKEYFILE="${DDPUSER}.key"
  if [ -f secrets/${DDP_PUBLICKEYFILE} ]; then
    ssh-keygen -f ${DDPUSER} <<< "y"
  else
    ssh-keygen -f ${DDPUSER} 
  fi
else
  DDP_PUBLICKEYFILE="ddp.id_rsa.pub"
  DDP_PRIVATEKEYFILE="ddp.id_rsa"
fi

echo "Creating ddp user"
# create ddp user, add to docker group
ssh -i secrets/${ROOT_PEMFILE} ubuntu@${MACHINE_IP} sudo adduser --gecos "DDPUser" --ingroup docker --disabled-password ${DDPUSER}
ssh -i secrets/${ROOT_PEMFILE} ubuntu@${MACHINE_IP} sudo usermod -a -G docker,sudo ${DDPUSER}

echo "Copying ddp user's public key over for ssh login"
# copy over the ssh key so we can ssh in
ssh -i secrets/${ROOT_PEMFILE} ubuntu@${MACHINE_IP} sudo mkdir /home/${DDPUSER}/.ssh
# use ssh-copy-id ?
scp -i secrets/${ROOT_PEMFILE} secrets/${DDP_PUBLICKEYFILE} ubuntu@${MACHINE_IP}:/home/ubuntu/.ssh/${DDP_PUBLICKEYFILE}
ssh -i secrets/${ROOT_PEMFILE} ubuntu@${MACHINE_IP} sudo install -D /home/ubuntu/.ssh/${DDP_PUBLICKEYFILE} /home/${DDPUSER}/.ssh/authorized_keys
ssh -i secrets/${ROOT_PEMFILE} ubuntu@${MACHINE_IP} sudo chown -R ${DDPUSER} /home/${DDPUSER}/.ssh
ssh -i secrets/${ROOT_PEMFILE} ubuntu@${MACHINE_IP} sudo chmod 700 /home/${DDPUSER}/.ssh
ssh -i secrets/${ROOT_PEMFILE} ubuntu@${MACHINE_IP} sudo chmod 600 /home/${DDPUSER}/.ssh/authorized_keys

# create venv
echo "Creating python3 venv"
ssh -i secrets/${DDP_PRIVATEKEYFILE} ddp@${MACHINE_IP} "python3 -m venv venv"
ssh -i secrets/${DDP_PRIVATEKEYFILE} ddp@${MACHINE_IP} "venv/bin/pip install jupyter"

# reboot 
echo "Restarting machine"
ssh -i secrets/${ROOT_PEMFILE} ubuntu@${MACHINE_IP} sudo reboot
