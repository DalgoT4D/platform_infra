#!/bin/sh

MACHINE_IP=`cat machineip.txt`

if [ "x${MACHINE_IP}" == "x" ]; then
  echo "Please set MACHINE_IP before running this script"
  exit 1
fi

DDPUSER="ddp"

# run ssh-keygen on local machine for development builds
# for production we need a stronger guarantee that we won't be locked out, so we re-use a known key pair
if [ "x${PROD}" == "x" ]; then
  DDP_PRIVATEKEYFILE="secrets/${DDPUSER}"
  if [ ! -f ${DDP_PRIVATEKEYFILE} ]; then
    echo "Private key missing for ${DDPUSER} please run scaffold-2"
    exit 1
  fi
else
  DDP_PRIVATEKEYFILE="secrets/ddp.id_rsa"
fi

ssh -i ${DDP_PRIVATEKEYFILE} ddp@${MACHINE_IP} "venv/bin/pip install prefect prefect-airbyte prefect-dbt"
# ssh -i ${DDP_PRIVATEKEYFILE} ddp@${MACHINE_IP} "venv/bin/pip install uvicorn"

DATABASE_USER=`grep PREFECT_DATABASE_USER dbcreds.txt | cut -d "=" -f 2`
DATABASE_PASSWORD=`grep PREFECT_DATABASE_PASSWORD dbcreds.txt | cut -d "=" -f 2`
DATABASE_HOST=`grep PREFECT_DATABASE_HOST dbcreds.txt | cut -d "=" -f 2`
DATABASE_DB=`grep PREFECT_DATABASE_DB dbcreds.txt | cut -d "=" -f 2`

connurl="postgresql+asyncpg://${DATABASE_USER}:${DATABASE_PASSWORD}@${DATABASE_HOST}:5432/${DATABASE_DB}"
cmd_setconnurl="venv/bin/prefect config set PREFECT_API_DATABASE_CONNECTION_URL=${connurl}"
ssh -i ${DDP_PRIVATEKEYFILE} ddp@${MACHINE_IP} ${cmd_setconnurl}

scp -i ${DDP_PRIVATEKEYFILE} _startprefect.sh ddp@${MACHINE_IP}:/home/ddp/startprefect.sh
ssh -i ${DDP_PRIVATEKEYFILE} ddp@${MACHINE_IP} "sh startprefect.sh"
