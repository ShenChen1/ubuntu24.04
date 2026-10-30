#!/bin/sh
# Qt EGLFS / Mali GPU direct rendering configuration for ArmSoM CM5 (RK3576)

export QT_QPA_PLATFORM=eglfs
export QT_QPA_EGLFS_INTEGRATION=eglfs_kms
export QT_QPA_EGLFS_KMS_CONFIG=/etc/qt-kms.json
export QT_QPA_EGLFS_FORCE888=1
export QT_QPA_FONTDIR=/usr/share/fonts
export QT_QPA_ENABLE_TERMINAL_KEYBOARD=1

# Rockchip Mali & DRM hints
export MALI_GPU_DEVICE=/dev/mali0
export DRM_CARD_DEVICE=/dev/dri/card0
