# jupyter-geo
Jupyter Lab for Geo ( Sentinel -2 )


docker run -p 8888:8888 \
-e JUPYTER_ENABLE_LAB=yes \
-e JUPYTER_TOKEN=yourtoken \
--name jupyter \
-v /srv/jupyter/:/home/data/ \
-d magnoabreu/jupyter:1.0
