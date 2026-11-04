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

finish() {
    sudo umount $TARGET_ROOTFS_DIR/dev
    exit -1
}
trap finish ERR

echo -e "\033[47;36m Extract image \033[0m"
sudo rm -rf $TARGET_ROOTFS_DIR
sudo tar -xpf ubuntu-base-$TARGET-$ARCH-*.tar.gz

# packages folder
sudo mkdir -p $TARGET_ROOTFS_DIR/packages
sudo cp -rpf packages/$ARCH/* $TARGET_ROOTFS_DIR/packages

#GPU/CAMERA/QT5 packages folder
install_packages
sudo mkdir -p $TARGET_ROOTFS_DIR/packages/install_packages
sudo cp -rpfv packages/$ARCH/libmali/$MALI_PKG.deb $TARGET_ROOTFS_DIR/packages/install_packages
sudo cp -rpfv packages/$ARCH/${ISP:0:5}/camera_engine_$ISP*.deb $TARGET_ROOTFS_DIR/packages/install_packages
if [ "$TARGET" == "server" ] && [ -d "packages/$ARCH/qt5" ]; then
    sudo cp -rpfv packages/$ARCH/qt5/anima-qt5-eglfs-runtime_*.deb $TARGET_ROOTFS_DIR/packages/install_packages
fi

#linux kernel deb
if [ -e ../linux-headers* ]; then
    Image_Deb=$(basename ../linux-headers*)
    sudo mkdir -p $TARGET_ROOTFS_DIR/boot/kerneldeb
    sudo touch $TARGET_ROOTFS_DIR/boot/build-host
    sudo cp -vrpf ../${Image_Deb} $TARGET_ROOTFS_DIR/boot/kerneldeb
    sudo cp -vrpf ../${Image_Deb/headers/image} $TARGET_ROOTFS_DIR/boot/kerneldeb
fi

# overlay folder
sudo cp -rpf overlay/* $TARGET_ROOTFS_DIR/

# overlay-firmware folder
sudo cp -rpf overlay-firmware/* $TARGET_ROOTFS_DIR/

# overlay-debug folder
# adb, video, camera  test file
if [ "$VERSION" == "debug" ]; then
    sudo cp -rpf overlay-debug/* $TARGET_ROOTFS_DIR/
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

ID=$(stat --format %u $TARGET_ROOTFS_DIR)

cat << EOF | sudo chroot $TARGET_ROOTFS_DIR

# Fixup owners
if [ "$ID" -ne 0 ]; then
    find / -user $ID -exec chown -h 0:0 {} \;
fi
for u in \$(ls /home/); do
    chown -h -R \$u:\$u /home/\$u
done

apt-get update
apt-get upgrade -y

chmod o+x /usr/lib/dbus-1.0/dbus-daemon-launch-helper
chmod +x /etc/rc.local

export DEBIAN_FRONTEND=noninteractive
export APT_INSTALL="apt-get install -fy --allow-downgrades"

echo -e "\033[47;36m ---------- armsom -------- \033[0m"
apt purge initramfs-tools -y

\${APT_INSTALL} dialog u-boot-tools edid-decode logrotate fdisk
if [[ "$TARGET" == "gnome" || "$TARGET" == "gnome-full" ]]; then
    \${APT_INSTALL} gdisk
    #Desktop background picture
    ln -sf /usr/share/xfce4/backdrops/armsom-wallpaper.png /usr/share/backgrounds/warty-final-ubuntu.png
elif [[ "$TARGET" == "xfce" || "$TARGET" == "xfce-full" ]]; then
    \apt-get remove -y gnome-bluetooth
    \${APT_INSTALL} bluez bluez-tools 
    #Desktop background picture
    ln -sf /usr/share/xfce4/backdrops/armsom-wallpaper.png /usr/share/xfce4/backdrops/xubuntu-wallpaper.png
elif [ "$TARGET" == "server" ]; then
    \${APT_INSTALL} bluez bluez-tools
    echo -e "\033[47;36m ----- Install Runtime & Debug Tools (Headless Server) ----- \033[0m"
    \${APT_INSTALL} kmscube libinput10 libxkbcommon0 fonts-wqy-zenhei gdbserver strace \
        pulseaudio pulseaudio-utils libasound2-plugins \
        iptables nftables iproute2 python3-pip python3-venv vim-tiny
fi

\${APT_INSTALL} /packages/install_packages/*.deb

if [ "$TARGET" == "server" ]; then
    # Keep linux-headers in /boot/kerneldeb for backup, only install runtime kernel image
    \${APT_INSTALL} /boot/kerneldeb/linux-image-*.deb || true
else
    \${APT_INSTALL} /boot/kerneldeb/* || true
fi

echo -e "\033[47;36m ----- power management ----- \033[0m"
if [ "$TARGET" != "server" ]; then
    \${APT_INSTALL} pm-utils triggerhappy bsdmainutils
    cp /etc/Powermanager/triggerhappy.service  /lib/systemd/system/triggerhappy.service
else
    \${APT_INSTALL} bsdmainutils
fi
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
echo -e "\033[47;36m ------- move rknpu2 --------- \033[0m"
mv /packages/rknpu2/rknpu2.tar  /
fi

echo -e "\033[47;36m ----- Install rktoolkit ----- \033[0m"
\${APT_INSTALL} /packages/rktoolkit/*.deb

if [[ "$TARGET" == "gnome-full" || "$TARGET" == "xfce-full" ]]; then
    echo -e "\033[47;36m ------ Install scratch ------- \033[0m"
    \${APT_INSTALL} /packages/embedfire/scratch_*.deb
fi

if [ "$TARGET" == "server" ]; then
    echo -e "\033[47;36m ----- Strip compiler toolchains & unused daemons (Server) ----- \033[0m"
    apt-get purge -y --allow-change-held-packages \
        gcc gcc-13 gcc-13-aarch64-linux-gnu gcc-aarch64-linux-gnu \
        g++ g++-13 g++-13-aarch64-linux-gnu g++-aarch64-linux-gnu \
        cpp cpp-13 cpp-13-aarch64-linux-gnu cpp-aarch64-linux-gnu \
        libstdc++-13-dev libgcc-13-dev binutils binutils-aarch64-linux-gnu binutils-common libbinutils libasan8 \
        humanity-icon-theme adwaita-icon-theme vsftpd modemmanager 2>/dev/null || true
fi

apt autoremove -y

if [[ "$TARGET" == "gnome" || "$TARGET" == "gnome-full" ]]; then
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
systemctl disable hostapd 2>/dev/null || true
systemctl disable ModemManager.service 2>/dev/null || true
systemctl mask ModemManager.service 2>/dev/null || true
systemctl disable vsftpd.service 2>/dev/null || true
systemctl disable rkaiq_3A.service 2>/dev/null || true
systemctl disable triggerhappy.service 2>/dev/null || true
systemctl enable wifibt-init
rm -f /lib/systemd/system/wpa_supplicant@.service

# Ensure vi is available and properly configured
if [ -e /usr/bin/vim.tiny ]; then
    update-alternatives --set vi /usr/bin/vim.tiny 2>/dev/null || ln -sf /usr/bin/vim.tiny /usr/bin/vi
    if [ -f /etc/vim/vimrc.tiny ]; then
        sed -i 's/"set nocompatible/set nocompatible/' /etc/vim/vimrc.tiny 2>/dev/null || true
        grep -q "set backspace=" /etc/vim/vimrc.tiny || echo "set backspace=2" >> /etc/vim/vimrc.tiny
    fi
fi

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

# Ensure user armsom has direct access to GPU/DRM/input
usermod -aG video,render,input armsom 2>/dev/null || true

# fix: MACAddressPolicy 
truncate -s 0 /etc/machine-id
truncate -s 0 /var/lib/dbus/machine-id 2>/dev/null || true

# Clean desktop icons & docs for headless server
if [ "$TARGET" == "server" ]; then
    rm -rf /usr/share/icons/Adwaita /usr/share/icons/Humanity* /usr/share/icons/ubuntu-mono* 2>/dev/null || true
    rm -rf /usr/share/doc/* /usr/share/man/* /usr/share/groff/* /usr/share/info/* 2>/dev/null || true
fi

# Strip unneeded PC/USB wireless firmwares for RK3576 (board only uses AP6275P and rockchip)
if [ "$SOC" == "rk3576" ]; then
    rm -rf /usr/lib/firmware/intel /usr/lib/firmware/rtw89 /usr/lib/firmware/aic8800 \
           /usr/lib/firmware/mediatek /usr/lib/firmware/rtlwifi /usr/lib/firmware/rtl_bt \
           /usr/lib/firmware/rtw88 /usr/lib/firmware/rtl_nic 2>/dev/null || true
fi

rm -rf /home/$(whoami)
rm -rf /var/lib/apt/lists/*
rm -rf /var/cache/
rm -rf /packages/
rm -rf /boot/*
rm -rf /root/.bash_history

EOF

./ch-mount.sh -u $TARGET_ROOTFS_DIR

source ./mk-image.sh 
