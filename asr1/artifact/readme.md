

docker build -t is21-cs-e2e_image -f artifact/dockerfile artifact

docker run --rm --gpus all -v ${PWD}:/workspace is21-cs-e2e_image tmux
