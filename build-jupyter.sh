#! /bin/sh

cd jupyter
docker ps -a | awk '{ print $1,$2 }' | grep magnoabreu/jupyter:1.0 | awk '{print $1 }' | xargs -I {} docker rm -f {}
docker rmi magnoabreu/jupyter:1.0
DOCKER_BUILDKIT=1 docker build --tag=magnoabreu/jupyter:1.0 --rm=true .


docker run -p 8888:8888 \
-e JUPYTER_ENABLE_LAB=yes \
-e JUPYTER_TOKEN=yourtoken \
--name jupyter \
-v /srv/jupyter/:/home/data/ \
-d magnoabreu/jupyter:1.0


chmod 0777 /srv/jupyter/