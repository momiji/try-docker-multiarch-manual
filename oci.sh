#!/bin/bash
set -Eeuo pipefail
action=$1
folder=$2

pack=$folder/.pack
sha=$folder/blobs/sha256

from_sha() { cat ${1:--} | tr -d '"' | cut -d: -f2 ; }
to_sha() { cat ${1:--} | sed -r 's/(.*)/"sha256:\1"/' ; }
hash() { echo '{"h":"sha256:'$(sha256sum "$1" | awk '{print $1}')'","s":'$(stat -c%s "$1")'}' ; }
inst() { h=$( sha256sum "$1" | awk '{print $1}' ) ; cp "$1" "$sha/$h" ; }

if [ "$action" = "unpack" ]; then
    rm -rf $pack
    mkdir $pack

    index=$( cat $folder/index.json | jq '.manifests[0].digest' -rc | from_sha )
    config=$( cat $sha/$index | jq '.config.digest' -rc | from_sha )
    arch=$( cat $sha/$config | jq '[.architecture,.os,.variant]|join("-")' -rc )
    mkdir $pack/$arch
    cat $sha/$config | jq '{"architecture":.architecture,"os":.os,"variant":.variant}' > $pack/$arch/platform
    cat $sha/$index | jq '.layers[].digest' -rc | from_sha > $pack/$arch/layers
    cat $sha/$config | jq '.rootfs.diff_ids[]' -rc | from_sha > $pack/$arch/diffs
    cat $sha/$config | jq '.history[]' -c > $pack/$arch/history
    cat $sha/$config | jq > $pack/$arch/config.json
fi

if [ "$action" = "pack" ]; then
    for arch in $( ls $pack ); do
        cat $pack/$arch/config.json | \
            jq '.os=$platform[0].os|.architecture=$platform[0].architecture|.variant=$platform[0].variant|.rootfs.diff_ids=$diffs | .history=$history' \
            --slurpfile platform $pack/$arch/platform \
            --slurpfile history $pack/$arch/history \
            --slurpfile diffs <( to_sha $pack/$arch/diffs ) \
            -c | tr -d '\n' > $pack/$arch/pack-config.json
        inst $pack/$arch/pack-config.json
        hash $pack/$arch/pack-config.json > $pack/$arch/pack-config
        for layer in $( cat $pack/$arch/layers ); do
            hash $sha/$layer >> $pack/$arch/pack-layers
        done
        echo '
            {
                "schemaVersion": 2,
                "mediaType": "application/vnd.oci.image.manifest.v1+json",
                "config": {
                    "mediaType": "application/vnd.oci.image.config.v1+json",
                    "digest": "sha256:8f503172f0a5d3f2466010fccfa0ff2e7b404dafd4be90aae4e2e224d9699b9f",
                    "size": 981
                },
                "layers": [
                    {
                    "mediaType": "application/vnd.oci.image.layer.v1.tar+gzip",
                    "digest": "sha256:dfd828479e4d8a183aa2b24163e9097e06d83d2948286fd874963bfd68c2e834",
                    "size": 116
                    }
                ]
            }
            ' | jq '.config.digest=$config[0].h|.config.size=$config[0].s|.layers=[$layers[]|{"mediaType":"application/vnd.oci.image.layer.v1.tar+gzip","digest":.h,"size":.s}]' \
            --slurpfile config $pack/$arch/pack-config \
            --slurpfile layers $pack/$arch/pack-layers \
            -c | tr -d '\n' > $pack/$arch/pack-index.json
        inst $pack/$arch/pack-index.json
        hash $pack/$arch/pack-index.json | jq '
            {
                "mediaType":"application/vnd.oci.image.manifest.v1+json",
                "digest":.h,
                "size":.s,
                "platform":$platform[0]
            }
            ' --slurpfile platform $pack/$arch/platform -c >> $pack/pack-platforms
    done
    echo '
        {
            "schemaVersion":2,
            "mediaType":"application/vnd.oci.image.index.v1+json",
            "manifests":[]
        }' | jq '.manifests=$platforms' \
            --slurpfile platforms $pack/pack-platforms \
            -c | tr -d '\n' > $pack/pack-index.json
    inst $pack/pack-index.json
    hash $pack/pack-index.json | jq '
        {
            "schemaVersion":2,
            "manifests":[
                {
                    "mediaType":"application/vnd.oci.image.index.v1+json",
                    "digest":.h,
                    "size":.s
                }
            ]
        }' -c | tr -d '\n' > $pack/pack-manifest.json
    cp $pack/pack-manifest.json $folder/index.json
fi

exit 0
