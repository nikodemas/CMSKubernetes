#!/bin/bash

### This script is to be used for running the WMAgent docker container at a VM
### Its sole purpose is to set all the needed mount points from the Host VM. Create
### all proper links at the host pointing to the currently executing container's tag and
### run the docekr cointainer. The Default docker image tag to be searched for execution is
### `latest`.

help(){
    echo -e $*
    cat <<EOF

The script to be used for running a WMAgent docker container at a VM.

Usage: wmagent-docker-run.sh [-t <wmagent_tag] [-p]

    -t <wmagent_tag>  The WMAgent version/tag to be downloaded from registry.cern.ch [Default:latest]
    -p <pull_image>   Bool flag to pull the image from registry.cern.ch [Default:False]


Example: ./wmagent-docker-run.sh -t 2.2.3.2 -p

EOF
}

usage(){
    help $*
    exit 1
}

PULL=false
WMA_TAG=latest

### Argument parsing:
while getopts ":t:hp" opt; do
    case ${opt} in
        t) WMA_TAG=$OPTARG ;;
        p) PULL=true ;;
        h) help; exit $? ;;
        : )
            msg="Invalid Option: -$OPTARG requires an argument"
            usage "$msg" ;;
    esac
done


wmaUser=cmst1
wmaOpts=" --user $wmaUser"

# This is the root at the host only, it may differ from the root inside the container.
# NOTE: This is parametriesed, so that the container can run on a different mount point.
#       A soft link is needed to mimic the same /data tree as inside the container so
#       that condor may find the job cache and working directories:
HOST_MOUNT_DIR=/data/dockerMount
[[ -h /data/srv/wmagent ]] && sudo rm -f /data/srv/wmagent
sudo ln -s $HOST_MOUNT_DIR/srv/wmagent /data/srv/wmagent


[[ -d $HOST_MOUNT_DIR/certs ]] || (sudo mkdir -p $HOST_MOUNT_DIR/certs) || exit $?
[[ -d $HOST_MOUNT_DIR/admin/wmagent ]] || (sudo mkdir -p $HOST_MOUNT_DIR/admin/wmagent) || exit $?
[[ -d $HOST_MOUNT_DIR/srv/wmagent/$WMA_TAG/install ]] || (sudo mkdir -p $HOST_MOUNT_DIR/srv/wmagent/$WMA_TAG/install) || exit $?
[[ -d $HOST_MOUNT_DIR/srv/wmagent/$WMA_TAG/config  ]] || (sudo mkdir -p $HOST_MOUNT_DIR/srv/wmagent/$WMA_TAG/config)  || exit $?
[[ -d $HOST_MOUNT_DIR/srv/wmagent/$WMA_TAG/logs ]] || { sudo mkdir -p $HOST_MOUNT_DIR/srv/wmagent/$WMA_TAG/logs ;} || exit $?

sudo chown -R $wmaUser $HOST_MOUNT_DIR/srv/wmagent/$WMA_TAG || exit $?

# NOTE: Before mounting /etc/tnsnames.ora we should check it exists, otherwise the run will fail on the FNAL agents
tnsMount=""
[[ -f /etc/tnsnames.ora ]] && tnsMount="--mount type=bind,source=/etc/tnsnames.ora,target=/etc/tnsnames.ora,readonly "

dockerOpts=" \
--network=host \
--rm \
--hostname=`hostname -f` \
--name=wmagent \
$tnsMount
--mount type=bind,source=/etc/condor,target=/etc/condor,readonly \
--mount type=bind,source=/tmp,target=/tmp \
--mount type=bind,source=$HOST_MOUNT_DIR/certs,target=/data/certs \
--mount type=bind,source=$HOST_MOUNT_DIR/srv/wmagent/$WMA_TAG/install,target=/data/srv/wmagent/current/install \
--mount type=bind,source=$HOST_MOUNT_DIR/srv/wmagent/$WMA_TAG/config,target=/data/srv/wmagent/current/config \
--mount type=bind,source=$HOST_MOUNT_DIR/srv/wmagent/$WMA_TAG/logs,target=/data/srv/wmagent/current/logs \
--mount type=bind,source=$HOST_MOUNT_DIR/admin/wmagent,target=/data/admin/wmagent/ \
"

wmaOpts="$wmaOpt $*"

$PULL && {
    echo "Pulling Docker image: registry.cern.ch/cmsweb/wmagent:$WMA_TAG"
    docker login registry.cern.ch
    docker pull registry.cern.ch/cmsweb/wmagent:$WMA_TAG
    docker tag registry.cern.ch/cmsweb/wmagent:$WMA_TAG local/wmagent:$WMA_TAG
    docker tag registry.cern.ch/cmsweb/wmagent:$WMA_TAG local/wmagent:latest
}

echo "Checking if there is no other wmagent container running and creating a link to the $WMA_TAG in the host mount area."
[[ `docker container inspect -f '{{.State.Status}}' wmagent 2>/dev/null ` == 'running' ]] || (
    [[ -h $HOST_MOUNT_DIR/srv/wmagent/current ]] && sudo rm -f $HOST_MOUNT_DIR/srv/wmagent/current
    sudo ln -s $HOST_MOUNT_DIR/srv/wmagent/$WMA_TAG $HOST_MOUNT_DIR/srv/wmagent/current )

echo "Starting the wmagent:$WMA_TAG docker container with the following parameters: $wmaOpts"
docker run $dockerOpts local/wmagent:$WMA_TAG $wmaOpts
