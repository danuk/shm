docker build -t danuk/shm-api --target api .
docker push danuk/shm-api

docker build -t danuk/shm --target core .
docker push danuk/shm

