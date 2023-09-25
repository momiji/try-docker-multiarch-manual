# try-docker-multiarch-manual
Try to build multiarch docker images without buildx

1. start local registry ./registry.sh
2. build: ./build2.sh
3. test: docker run --rm -it localhost:5000/am
