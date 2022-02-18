# Jupyter Lab for Geo ( Sentinel -2 )

Here is my Jupyter Docker to work on Sentinel 2 images.
It is based on base-notebook from https://github.com/jupyter/docker-stacks/blob/master/base-notebook/Dockerfile
and comes with a lot of geo related stuff.

```
docker run -p 8888:8888 \
-e JUPYTER_ENABLE_LAB=yes \
-e JUPYTER_TOKEN=yourtoken \
--name jupyter \
-v /srv/jupyter/:/home/data/ \
-d magnoabreu/jupyter:1.0
```
