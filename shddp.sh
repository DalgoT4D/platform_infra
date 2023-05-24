#!/bin/sh

MACHINE_IP=`cat machineip.txt`

if [ $# -gt 0 ]
then
  ssh -i secrets/ddp.key ddp@${MACHINE_IP}
else
  ssh -i secrets/ddp.key -L 8000:localhost:8000 \
                       -L 9876:localhost:8888 \
                       -L 9081:localhost:8081 \
                       -L 9082:localhost:8082 \
                       -L 9083:localhost:8083 \
                       -L 9000:localhost:9000 \
                       -L 3000:localhost:3000 \
                       -L 5555:localhost:5555 \
                       -L 4200:localhost:4200 \
    ddp@${MACHINE_IP}

fi
