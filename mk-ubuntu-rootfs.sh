#!/bin/bash -e

# Directory contains the target rootfs
TARGET_ROOTFS_DIR="binary"

if [ ! $SOC ]; then
    echo "---------------------------------------------------------"
    echo "please enter soc number:"
    echo "请输入要构建CPU的序号:"
    echo "[0] Exit Menu"
    echo "[1] rk3128"
    echo "[2] rk3528"
    echo "[3] rk3562"
    echo "[4] rk3566/rk3568"
    echo "[5] rk3576"
    echo "[6] rk3588/rk3588s"
    echo "---------------------------------------------------------"
    read input

    case $input in
        0)  exit ;;
        1)  SOC=rk3128 ;;
        2)  SOC=rk3528 ;;
        3)  SOC=rk3562 ;;
        4)  SOC=rk356x ;;
        5)  SOC=rk3576 ;;
        6)  SOC=rk3588 ;;
        *)  echo 'input soc number error, exit !'
            exit;;
    esac
    echo -e "\033[47;36m set SOC=$SOC...... \033[0m"
fi

if [ ! $TARGET ]; then
    echo "---------------------------------------------------------"
    echo "please enter TARGET version number:"
    echo "请输入要构建的根文件系统版本:"
    echo "[0] Exit Menu"
    echo "[1] gnome"
    echo "[2] xfce"
    echo "[3] server"
    echo "[4] gnome-full"
    echo "[5] xfce-full"
    echo "---------------------------------------------------------"
    read input

    case $input in
        0)  exit ;;
        1) TARGET=gnome ;;
        2) TARGET=xfce ;;
        3) TARGET=server ;;
        4) TARGET=gnome-full ;;
        5) TARGET=xfce-full ;;
        *)  echo -e "\033[47;36m input TARGET version number error, exit ! \033[0m"
            exit;;
    esac
    echo -e "\033[47;36m set TARGET=$TARGET...... \033[0m"
fi

install_packages() {
    case $SOC in
        rk3399|rk3399pro)
        MALI=midgard-t86x-r18p0
        MALI_PKG=libmali-*$MALI*-x11*
        ISP=rkisp
        ;;
        rk3328|rk3528)
        MALI=utgard-450
        MALI_PKG=libmali-*$MALI*-x11*
        ISP=rkisp
        MIRROR=carp-rk352x
        ;;
        rk3128|rk3036)
        MALI=utgard-400
        MALI_PKG=libmali-*$MALI*-x11*
        ISP=rkisp
        ;;
        rk3562)
        MALI=bifrost-g52-g13p0
        MALI_PKG=libmali-*$MALI*-x11-gbm*
        [[ "$TARGET" =~ ^gnome(-full)?$ ]] && MALI_PKG=libmali-*$MALI*-x11-wayland-gbm*
        ISP=rkaiq_rk3562
        MIRROR=carp-rk356x
        ;;
        rk356x|rk3566|rk3568)
        MALI=bifrost-g52-g13p0
        MALI_PKG=libmali-*$MALI*-x11-wayland-gbm*
        ISP=rkaiq_rk3568
        MIRROR=carp-rk356x
        ;;
        rk3576)
        MALI=bifrost-g52-g13p0
        MALI_PKG=libmali-*$MALI*-x11-wayland-gbm*
        ISP=rkaiq_rk3576
        ;;
        rk3588|rk3588s)
        MALI=valhall-g610-g24p0
        MALI_PKG=libmali-*$MALI*-x11-wayland-gbm*
        ISP=rkaiq_rk3588
        MIRROR=carp-rk3588
        ;;
    esac
}

case "${ARCH:-$1}" in
    arm|arm32|armhf)
        ARCH=armhf
        ;;
    *)
        ARCH=arm64
        ;;
esac

echo -e "\033[47;36m Building for $ARCH \033[0m"

if [ ! $VERSION ]; then
    VERSION="release"
fi

echo -e "\033[47;36m Building for $VERSION \033[0m"

if [ ! -e ubuntu-base-"$TARGET"-$ARCH-*.tar.gz ]; then
    echo "\033[41;36m Run mk-base-ubuntu.sh first \033[0m"
    exit -1
fi

load_kernel_deb_version() {
    if [ ! -r ../kernel/include/config/kernel.release ] || [ ! -r ../kernel/debian/changelog ]; then
        echo "ERROR: Missing kernel build metadata. Run ./build.sh kerneldeb in the SDK root first." >&2
        return 1
    fi
    if ! KERNEL_RELEASE=$(cat ../kernel/include/config/kernel.release); then
        echo "ERROR: Cannot read kernel.release." >&2
        return 1
    fi
    if [[ ! "$KERNEL_RELEASE" =~ ^[a-z0-9][a-z0-9.+-]*$ ]]; then
        echo "ERROR: Invalid kernel.release. Run ./build.sh kerneldeb in the SDK root first." >&2
        return 1
    fi
    if ! KERNEL_DEB_VERSION=$(dpkg-parsechangelog --file ../kernel/debian/changelog --show-field Version); then
        echo "ERROR: Cannot read the kernel deb version. Run ./build.sh kerneldeb in the SDK root first." >&2
        return 1
    fi
    if [ -z "$KERNEL_DEB_VERSION" ]; then
        echo "ERROR: Missing Version in kernel/debian/changelog." >&2
        return 1
    fi
}

find_kernel_deb() {
    local expected metadata deb
    local -a matches=()
    expected=$(printf '%s\t%s\t%s' "$1" "$2" "$3")
    for deb in ../*.deb; do
        [ -f "$deb" ] || continue
        if ! metadata=$(dpkg-deb --show --showformat='${Package}\t${Version}\t${Architecture}' "$deb"); then
            echo "WARNING: Cannot read deb metadata; ignoring $deb" >&2
            continue
        fi
        [ "$metadata" != "$expected" ] || matches+=("$deb")
    done
    case "${#matches[@]}" in
        0) return 1 ;;
        1) printf '%s\n' "${matches[0]}" ;;
        *)
            echo "ERROR: Multiple matching debs for $1 ($2, $3):" >&2
            printf '  %s\n' "${matches[@]}" >&2
            return 2
            ;;
    esac
}

load_kernel_deb_version
if ! KERNEL_IMAGE_DEB=$(find_kernel_deb "linux-image-$KERNEL_RELEASE" "$KERNEL_DEB_VERSION" "$ARCH"); then
    echo "ERROR: Cannot select linux-image-$KERNEL_RELEASE ($KERNEL_DEB_VERSION, $ARCH). Run ./build.sh kerneldeb in the SDK root or resolve duplicate packages." >&2
    exit 1
fi
echo "Selected kernel image deb: $KERNEL_IMAGE_DEB"
if ! KERNEL_HEADER_DEB=$(find_kernel_deb "linux-headers-$KERNEL_RELEASE" "$KERNEL_DEB_VERSION" "$ARCH"); then
    echo "ERROR: Cannot select linux-headers-$KERNEL_RELEASE ($KERNEL_DEB_VERSION, $ARCH). Run ./build.sh kerneldeb in the SDK root or resolve duplicate packages." >&2
    exit 1
fi
echo "Selected kernel headers deb: $KERNEL_HEADER_DEB"

finish() {
    if ! ./ch-mount.sh -u "$TARGET_ROOTFS_DIR"; then
        echo "ERROR: Failed to unmount rootfs after build failure; check remaining mounts before rebuilding." >&2
    fi
    exit 1
}
trap finish ERR

echo -e "\033[47;36m Extract image \033[0m"
sudo rm -rf $TARGET_ROOTFS_DIR
sudo tar -xpf ubuntu-base-$TARGET-$ARCH-*.tar.gz

# packages folder
sudo mkdir -p $TARGET_ROOTFS_DIR/packages
sudo cp -rpf packages/$ARCH/* $TARGET_ROOTFS_DIR/packages

#GPU/CAMERA packages folder
install_packages
sudo mkdir -p $TARGET_ROOTFS_DIR/packages/install_packages
sudo cp -rpfv packages/$ARCH/libmali/$MALI_PKG.deb $TARGET_ROOTFS_DIR/packages/install_packages
sudo cp -rpfv packages/$ARCH/${ISP:0:5}/camera_engine_$ISP*.deb $TARGET_ROOTFS_DIR/packages/install_packages

#linux kernel deb
sudo mkdir -p "$TARGET_ROOTFS_DIR/boot/kerneldeb"
sudo touch "$TARGET_ROOTFS_DIR/boot/build-host"
sudo cp -vpf "$KERNEL_IMAGE_DEB" "$TARGET_ROOTFS_DIR/boot/kerneldeb/linux-image.deb"
sudo cp -vpf "$KERNEL_HEADER_DEB" "$TARGET_ROOTFS_DIR/boot/kerneldeb/linux-headers.deb"

# overlay folder
sudo cp -rpf --no-preserve=ownership overlay/* $TARGET_ROOTFS_DIR/

# overlay-firmware folder
sudo cp -rpf --no-preserve=ownership overlay-firmware/* $TARGET_ROOTFS_DIR/

# overlay-debug folder
# adb, video, camera  test file
if [ "$VERSION" == "debug" ]; then
    sudo cp -rpf --no-preserve=ownership overlay-debug/* $TARGET_ROOTFS_DIR/
fi

## hack the serial
sudo cp -f overlay/usr/lib/systemd/system/serial-getty@.service $TARGET_ROOTFS_DIR/lib/systemd/system/serial-getty@.service

echo -e "\033[47;36m Change root.....................\033[0m"
if [ "$ARCH" == "armhf" ]; then
    sudo cp /usr/bin/qemu-arm-static $TARGET_ROOTFS_DIR/usr/bin/
elif [ "$ARCH" == "arm64"  ]; then
    sudo cp /usr/bin/qemu-aarch64-static $TARGET_ROOTFS_DIR/usr/bin/
fi

./ch-mount.sh -m $TARGET_ROOTFS_DIR

cat << EOF | sudo chroot $TARGET_ROOTFS_DIR

apt-get update
apt-get upgrade -y

chmod o+x /usr/lib/dbus-1.0/dbus-daemon-launch-helper
chmod +x /etc/rc.local

export DEBIAN_FRONTEND=noninteractive
export APT_INSTALL="apt-get install -fy --allow-downgrades"

echo -e "\033[47;36m ---------- anima -------- \033[0m"
apt purge initramfs-tools -y

\${APT_INSTALL} dialog toilet u-boot-tools edid-decode logrotate fdisk
if [[ "$TARGET" == "gnome" || "$TARGET" == "gnome-full" ]]; then
    \${APT_INSTALL} gdisk
    #Desktop background picture
    ln -sf /usr/share/xfce4/backdrops/anima-wallpaper.png /usr/share/backgrounds/warty-final-ubuntu.png
elif [[ "$TARGET" == "xfce" || "$TARGET" == "xfce-full" ]]; then
    \apt-get remove -y gnome-bluetooth
    \${APT_INSTALL} bluez bluez-tools 
    #Desktop background picture
    ln -sf /usr/share/xfce4/backdrops/anima-wallpaper.png /usr/share/xfce4/backdrops/xubuntu-wallpaper.png
elif [ "$TARGET" == "server" ]; then
    \${APT_INSTALL} bluez bluez-tools
fi

\${APT_INSTALL} /packages/install_packages/*.deb

if ! \${APT_INSTALL} /boot/kerneldeb/linux-image.deb /boot/kerneldeb/linux-headers.deb; then
    echo "ERROR: Kernel deb installation failed; aborting rootfs build." >&2
    exit 1
fi

echo -e "\033[47;36m ----- power management ----- \033[0m"
\${APT_INSTALL} pm-utils triggerhappy bsdmainutils
cp /etc/Powermanager/triggerhappy.service  /lib/systemd/system/triggerhappy.service
sed -i "s/#HandlePowerKey=.*/HandlePowerKey=ignore/" /etc/systemd/logind.conf

echo -e "\033[47;36m ----------- RGA  ----------- \033[0m"
\${APT_INSTALL} /packages/rga2/*.deb

if [[ "$TARGET" == "gnome" ||  "$TARGET" == "xfce" || "$TARGET" == "gnome-full" || "$TARGET" == "xfce-full" ]]; then
    echo -e "\033[47;36m ------ Setup Video---------- \033[0m"
    \${APT_INSTALL} gstreamer1.0-plugins-bad gstreamer1.0-plugins-base gstreamer1.0-plugins-ugly gstreamer1.0-tools gstreamer1.0-alsa \
    gstreamer1.0-plugins-base-apps

    \${APT_INSTALL} /packages/mpp/*
    \${APT_INSTALL} /packages/gst-rkmpp/*.deb
    \${APT_INSTALL} /packages/gstreamer/*.deb
elif [ "$TARGET" == "server" ]; then
    echo -e "\033[47;36m ------ Setup Video---------- \033[0m"
    \${APT_INSTALL} /packages/mpp/*
    \${APT_INSTALL} /packages/gst-rkmpp/*.deb
fi

if [[ "$TARGET" == "gnome" || "$TARGET" == "gnome-full" ]]; then
    echo -e "\033[47;36m ----- Install Xserver------- \033[0m"
    \${APT_INSTALL} /packages/xserver/*.deb
    apt-mark hold xserver-common xserver-xorg-core xserver-xorg-legacy xserver-xorg-dev
elif [[ "$TARGET" == "xfce" || "$TARGET" == "xfce-full" ]]; then
    echo -e "\033[47;36m ----- Install Xserver------- \033[0m"
    \${APT_INSTALL} /packages/xserver/*.deb
    apt-mark hold xserver-common xserver-xorg-core xserver-xorg-legacy xserver-xorg-dev
fi

if [[ "$TARGET" == "gnome" ||  "$TARGET" == "xfce" || "$TARGET" == "gnome-full" || "$TARGET" == "xfce-full" ]]; then
    echo -e "\033[47;36m ----- Install Camera ------- \033[0m"
    \${APT_INSTALL} cheese v4l-utils

    echo -e "\033[47;36m ----- Wayland/Weston ------- \033[0m"
    \${APT_INSTALL} libseat-dev
    \${APT_INSTALL} /packages/wayland/*.deb

    # echo -e "\033[47;36m ------ Install openbox ----- \033[0m"
    # \${APT_INSTALL} /packages/openbox/*.deb

    # echo -e "\033[47;36m --------- firefox-esr ------ \033[0m"
    # \${APT_INSTALL} /packages/firefox/*.deb
fi

echo -e "\033[47;36m ------- Install libdrm ------ \033[0m"
\${APT_INSTALL} /packages/libdrm/*.deb

if [[ "$TARGET" == "gnome" ||  "$TARGET" == "xfce" || "$TARGET" == "gnome-full" || "$TARGET" == "xfce-full" ]]; then
    echo -e "\033[47;36m ------ libdrm-cursor -------- \033[0m"
    \${APT_INSTALL} /packages/libdrm-cursor/*.deb

    if [ "$VERSION" == "debug" ]; then
        echo -e "\033[47;36m ------ Install glmark2 ------ \033[0m"
        \${APT_INSTALL} glmark2-es2
    fi
fi

if [ -e "/usr/lib/aarch64-linux-gnu" ] ; then
echo -e "\033[47;36m ----- unpack rknpu2 --------- \033[0m"
tar --no-same-owner -xf /packages/rknpu2/rknpu2.tar -C /
ldconfig
fi

echo -e "\033[47;36m ----- Install rktoolkit ----- \033[0m"
\${APT_INSTALL} /packages/rktoolkit/*.deb

if [[ "$TARGET" == "gnome-full" || "$TARGET" == "xfce-full" ]]; then
    echo -e "\033[47;36m ------ Install scratch ------- \033[0m"
    \${APT_INSTALL} /packages/embedfire/scratch_*.deb
fi

apt autoremove -y

if [[ "$TARGET" != "server" ]]; then
    \${APT_INSTALL} ubuntu-desktop

    add-apt-repository ppa:mozillateam/ppa && \
    echo 'Package: firefox*
Pin: release o=LP-PPA-mozillateam
Pin-Priority: 1001' | tee /etc/apt/preferences.d/mozilla-firefox && \
    apt-get update && \${APT_INSTALL} firefox
fi

# mark package to hold
apt list --upgradable | cut -d/ -f1 | xargs apt-mark hold

echo -e "\033[47;36m ------- Custom Script ------- \033[0m"
systemctl mask systemd-networkd-wait-online.service
systemctl mask NetworkManager-wait-online.service
systemctl disable hostapd
systemctl enable wifibt-init
rm /lib/systemd/system/wpa_supplicant@.service
if [ "$TARGET" == "server" ]; then
    # Server images run without X11; avoid invoking xrandr drm-hotplug on boot.
    rm -f /etc/udev/rules.d/65-rockchip-drm-hotplug.rules
fi

# Ubuntu 24.04 no longer ships pam_lastlog.so.
sed -i '/^[^#].*pam_lastlog\.so/s/^/# /' /etc/pam.d/login

echo -e "\033[47;36m  ---------- Clean ----------- \033[0m"
if [ -e "/usr/lib/arm-linux-gnueabihf/dri" ] ;
then
    # Only preload libdrm-cursor for X
    sed -i "1aexport LD_PRELOAD=/usr/lib/arm-linux-gnueabihf/libdrm-cursor.so.1" /usr/bin/X
    cd /usr/lib/arm-linux-gnueabihf/dri/
    cp kms_swrast_dri.so swrast_dri.so rockchip_dri.so /
    rm /usr/lib/arm-linux-gnueabihf/dri/*.so
    mv /*.so /usr/lib/arm-linux-gnueabihf/dri/
elif [ -e "/usr/lib/aarch64-linux-gnu/dri" ];
then
    # Only preload libdrm-cursor for X
    sed -i "1aexport LD_PRELOAD=/usr/lib/aarch64-linux-gnu/libdrm-cursor.so.1" /usr/bin/X
    cd /usr/lib/aarch64-linux-gnu/dri/
    cp kms_swrast_dri.so swrast_dri.so rockchip_dri.so /
    rm /usr/lib/aarch64-linux-gnu/dri/*.so
    mv /*.so /usr/lib/aarch64-linux-gnu/dri/
    rm /etc/profile.d/qt.sh
fi

// fix: MACAddressPolicy 
truncate -s 0 /etc/machine-id
truncate -s 0 /var/lib/dbus/machine-id 2>/dev/null || true

rm -rf /home/$(whoami)
rm -rf /var/lib/apt/lists/*
rm -rf /var/cache/
rm -rf /packages/
rm -rf /boot/*
rm -rf /root/.bash_history

EOF

./ch-mount.sh -u $TARGET_ROOTFS_DIR

source ./mk-image.sh 
