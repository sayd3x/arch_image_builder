#/bin/bash

BUILT_IMAGE=$(docker build -q .)
CONTAINER_ID=$(docker create -t --privileged $BUILT_IMAGE /bin/bash /root/start.sh)
docker start -a $CONTAINER_ID &&
docker cp $CONTAINER_ID:/root/bootstrap/hdd.image ./archminer.img &&
docker rm $CONTAINER_ID
