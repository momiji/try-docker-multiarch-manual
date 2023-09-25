set -Eeuo pipefail
image=ma
version=latest
base_url=docker.io
#base_image=amazoncorretto
#base_version=21.0.0
base_image=alpine
base_version=3.18.3

[ -d acs ] || {
    docker pull $base_image:$base_version --platform linux/amd64
    docker tag $base_image:$base_version $base_image:$base_version-amd64
    docker rmi $base_image:$base_version
    skopeo copy docker-daemon:$base_image:$base_version-amd64 oci:acs
    # acs_digest=$( skopeo inspect docker://$base_url/$base_image:$base_version --raw | jq '.manifests[] | select(.platform.architecture=="amd64").digest' -r )
    # skopeo copy docker://$base_url/$base_image@$acs_digest oci:acs
}

[ -d acr ] || {
    docker pull $base_image:$base_version --platform linux/arm64
    docker tag $base_image:$base_version $base_image:$base_version-arm64
    docker rmi $base_image:$base_version
    skopeo copy docker-daemon:$base_image:$base_version-arm64 oci:acr
    # acr_digest=$( skopeo inspect docker://$base_url/$base_image:$base_version --raw | jq '.manifests[] | select(.platform.architecture=="arm64").digest' -r )
    # skopeo copy docker://$base_url/$base_image@$acr_digest oci:acr
}

[ -f abuild ] || {
    docker build . -t $image:$version-amd64
    skopeo copy docker-daemon:$image:$version-amd64 docker://localhost:5000/$image:$version-amd64 --dest-tls-verify=false
    touch abuild
}

[ -d amt ] || {
    skopeo copy docker-daemon:$image:$version-amd64 oci:amt
}

rm -rf amr
mkdir amr amr/blobs amr/blobs/sha256

# count base image source layers
a=$( cat acs/index.json | jq .manifests[].digest -r | cut -d: -f2 )
count=$( echo "$a" | wc -l )

# copy base image replacement
b=$( cat acr/index.json | jq .manifests[].digest -r | cut -d: -f2 )
l=$( cat acr/blobs/sha256/$b | jq .layers[].digest -r | cut -d: -f2 )
for i in $l ; do
    cp acr/blobs/sha256/$i amr/blobs/sha256/
done

# copy built image additions
c=$( cat amt/index.json | jq .manifests[].digest -r | cut -d: -f2 )
l=$( cat amt/blobs/sha256/$c | jq .layers[].digest -r | cut -d: -f2 )
#l=$( echo "$l" | tail -n +$(($count+1)) )
#for i in $l ; do
#    cp amt/blobs/sha256/$i amr/blobs/sha256/
#done
cp -R amt/blobs/sha256/* amr/blobs/sha256/
cp amt/oci-layout amr/

# copy built image config
d=$( cat amt/index.json | jq .manifests[].digest -r | cut -d: -f2 )
l=$( cat amt/blobs/sha256/$d | jq .config.digest -r | cut -d: -f2 )
# cp -v amt/blobs/sha256/$l amr/blobs/sha256/
cat amt/blobs/sha256/$l | jq '.architecture="arm64"|.variant="v8"' -c | tr -d '\n' > amr.json
h=$( cat amr.json | sha256sum | awk '{print $1}' )
s=$( stat -c%s amr.json )
cp -v amr.json amr/blobs/sha256/$h

# copy built image layers list
#cat amt/blobs/sha256/$d | jq '.config.digest="sha256:"+$h' --arg h "$h"
#cat acr/blobs/sha256/$b | jq .layers
echo '{"count":'$count',"h": "'$h'","s":'$s'}' | jq '.layers=$l[0].layers' --slurpfile l acr/blobs/sha256/$b > amr.conf
cat amt/blobs/sha256/$c | jq '.config.digest="sha256:"+$c[0].h | .config.size=$c[0].s | .layers = $c[0].layers + .layers[$c[0].count:(.layers|length)]' --slurpfile c amr.conf -c | tr -d '\n' > amr.list
h=$( cat amr.list | sha256sum | awk '{print $1}' )
s=$( stat -c%s amr.list )
cp -v amr.list amr/blobs/sha256/$h

# copy built image index
cat amt/index.json | jq '.manifests[0].digest="sha256:"+$c.h | .manifests[0].size=$c.s' --argjson c '{"h":"'$h'", "s": '$s' }' -c | tr -d '\n' > amr/index.json

# mix index
cat amt/index.json | jq '.manifests[0].platform={"os":"linux","architecture":"amd64"}' > a1.json
cat amr/index.json | jq '.manifests[0].platform={"os":"linux","architecture":"arm64","variant":"v8"}' > a2.json
cat amt/index.json | jq '.mediaType="application/vnd.oci.image.index.v1+json" | .manifests=[$a1[0].manifests[0],$a2[0].manifests[0]]' --slurpfile a1 a1.json --slurpfile a2 a2.json -c > amr.multi
h=$( cat amr.multi | sha256sum | awk '{print $1}' )
s=$( stat -c%s amr.multi )
cp -v amr.multi amr/blobs/sha256/$h
cat amt/index.json | jq '.manifests[0].mediaType="application/vnd.oci.image.index.v1+json" | .manifests[0].digest="sha256:"+$c.h | .manifests[0].size=$c.s' --argjson c '{"h":"'$h'", "s": '$s' }' -c | tr -d '\n' > amr/index.json

docker run --rm -it --network=host -v $PWD/amr:/amr quay.io/skopeo/stable:latest copy --multi-arch all oci:amr docker://localhost:5000/am:latest --dest-tls-verify=false

exit 123

skopeo copy oci:amr docker://localhost:5000/$image:$version --dest-tls-verify=false
# copy to target repository

skopeo copy oci:amr docker://localhost:5000/$image:$version-arm64 --dest-tls-verify=false

set -x
docker pull localhost:5000/$image:$version-amd64
docker pull localhost:5000/$image:$version-arm64
docker manifest create localhost:5000/$image:$version localhost:5000/$image:$version-amd64 localhost:5000/$image:$version-arm64
docker manifest push localhost:5000/$image:$version

docker run --rm -it localhost:5000/$image:$version
