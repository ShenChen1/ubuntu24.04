#!/bin/bash
set -eo pipefail

function mnt() {
    local rootfs_dir="$2"
    echo "MOUNTING: $rootfs_dir"

    sudo mkdir -p "$rootfs_dir/proc" "$rootfs_dir/sys" "$rootfs_dir/dev"
    mountpoint -q "$rootfs_dir/proc" || sudo mount -t proc /proc "$rootfs_dir/proc"
    mountpoint -q "$rootfs_dir/sys" || sudo mount -t sysfs /sys "$rootfs_dir/sys"
    mountpoint -q "$rootfs_dir/dev" || sudo mount -o bind /dev "$rootfs_dir/dev"
    sudo mkdir -p "$rootfs_dir/dev/pts"
    mountpoint -q "$rootfs_dir/dev/pts" || sudo mount -t devpts devpts "$rootfs_dir/dev/pts"
}

function unmount_entry() {
    local target="$1"
    if ! mountpoint -q "$target"; then
        return 0
    fi

    sudo umount "$target"
}

function umnt() {
    local rootfs_dir="$2"
    echo "UNMOUNTING: $rootfs_dir"
    local failed=0

    # Unmount in reverse order to respect hierarchy
    local mountpoints=(
        "$rootfs_dir/dev/pts"
        "$rootfs_dir/dev"
        "$rootfs_dir/sys"
        "$rootfs_dir/proc"
    )

    for mp in "${mountpoints[@]}"; do
        unmount_entry "$mp" || failed=1
    done

    # Verify no mountpoints remain
    for mp in "${mountpoints[@]}"; do
        if mountpoint -q "$mp"; then
            echo "ERROR: Failed to unmount $mp" >&2
            failed=1
        fi
    done

    return $failed
}


if [ "$1" == "-m" ] && [ -n "$2" ] ;
then
    mnt $1 $2
elif [ "$1" == "-u" ] && [ -n "$2" ];
then
    umnt $1 $2
else
    echo ""
    echo "Either 1'st, 2'nd or both parameters were missing"
    echo ""
    echo "1'st parameter can be one of these: -m(mount) OR -u(umount)"
    echo "2'nd parameter is the full path of rootfs directory"
    echo ""
    echo "For example: ch-mount.sh -m /media/sdcard"
    echo ""
    echo 1st parameter : ${1}
    echo 2nd parameter : ${2}
    exit 1
fi
