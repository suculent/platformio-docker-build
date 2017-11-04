DOCKER_HUB_REPO=suculent/$(basename $(pwd))
docker build . -t $DOCKER_HUB_REPO
if [[ $?==0 ]]; then
  docker push $DOCKER_HUB_REPO
fi
