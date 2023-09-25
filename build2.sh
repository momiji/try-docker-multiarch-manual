set -Eeuo pipefail
image=ma
version=latest
base_url=docker.io
#base_image=amazoncorretto
#base_version=21.0.0
base_image=ubuntu
base_version=22.04

skop() {
    f=$1
    shift
    [ -d "$f" ] || mkdir "$f"
    docker run --rm -it --network=host -e USER_UID=$UID -e DOCKER_GID=137 \
        -v /run/docker.sock:/run/docker.sock \
        -v "$PWD/$f":"/$f" \
        -v $PWD/skopeo-entrypoint.sh:/skopeo-entrypoint.sh \
        --entrypoint /skopeo-entrypoint.sh \
        quay.io/skopeo/stable:latest "$@"
}

[ -d acs ] || {
    docker pull $base_image:$base_version --platform linux/amd64
    docker tag $base_image:$base_version $base_image:$base_version-amd64
    docker rmi $base_image:$base_version
    skop acs copy docker-daemon:$base_image:$base_version-amd64 oci:acs
    # acs_digest=$( skopeo inspect docker://$base_url/$base_image:$base_version --raw | jq '.manifests[] | select(.platform.architecture=="amd64").digest' -r )
    # skopeo copy docker://$base_url/$base_image@$acs_digest oci:acs
}

[ -d acr ] || {
    docker pull $base_image:$base_version --platform linux/arm/v7
    docker tag $base_image:$base_version $base_image:$base_version-armv7
    docker rmi $base_image:$base_version
    skop acr copy docker-daemon:$base_image:$base_version-armv7 oci:acr
    # acr_digest=$( skopeo inspect docker://$base_url/$base_image:$base_version --raw | jq '.manifests[] | select(.platform.architecture=="arm64").digest' -r )
    # skopeo copy docker://$base_url/$base_image@$acr_digest oci:acr
}

[ -f abuild ] || {
    docker build . -t $image:$version-amd64
    skop acr copy docker-daemon:$image:$version-amd64 docker://localhost:5000/$image:$version-amd64 --dest-tls-verify=false
    touch abuild
}

[ -d ams ] || {
    skop ams copy docker-daemon:$image:$version-amd64 oci:ams
}

rm -rf amr
mkdir amr amr/blobs amr/blobs/sha256

./oci.sh unpack acr
./oci.sh unpack acs
./oci.sh unpack ams

# copy ams to amr
cp -R acs/.pack amr/
for layer in $( cat acs/.pack/*/layers ); do
    cp acs/blobs/sha256/$layer amr/blobs/sha256/
done

cp -R acr/.pack amr/
for layer in $( cat acr/.pack/*/layers ); do
    cp acr/blobs/sha256/$layer amr/blobs/sha256/
done

# override config.json
for platform in $( ls amr/.pack ); do
    cp ams/.pack/*/config.json amr/.pack/$platform
done

# compute additional diffs to apply from ams
a=$( cat acs/.pack/*/diffs | wc -l )
b=$( cat ams/.pack/*/diffs | wc -l )
diffs=$((b-a))
for platform in $( ls amr/.pack ); do
    cat ams/.pack/*/diffs | tail -n -$diffs >> amr/.pack/$platform/diffs
done

# compute additional history to apply from ams
a=$( cat acs/.pack/*/history | wc -l )
b=$( cat ams/.pack/*/history | wc -l )
history=$((b-a))
for platform in $( ls amr/.pack ); do
    cat ams/.pack/*/history | tail -n -$history >> amr/.pack/$platform/history
done

# compute additional layers to apply from ams
a=$( cat acs/.pack/*/layers | wc -l )
b=$( cat ams/.pack/*/layers | wc -l )
layers=$((b-a))
for platform in $( ls amr/.pack ); do
    cat ams/.pack/*/layers | tail -n -$layers >> amr/.pack/$platform/layers
done
for layer in $( cat ams/.pack/*/layers | tail -n +$((layers+1)) ); do
    cp ams/blobs/sha256/$layer amr/blobs/sha256/
done

# generate new configuration
./oci.sh pack amr

# push multi-arch image to the registry
skop amr copy --multi-arch all oci:amr docker://localhost:5000/am:latest --dest-tls-verify=false
#docker run --rm -it --network=host -v $PWD/amr:/amr quay.io/skopeo/stable:latest copy --multi-arch all oci:amr docker://localhost:5000/am:latest --dest-tls-verify=false

#
exit 0
