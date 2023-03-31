#!/bin/sh

MACHINE_IP=`cat machineip.txt`

ssh -i secrets/ddp.key -L 8000:localhost:8000 -L 9876:localhost:8888 ddp@${MACHINE_IP}
