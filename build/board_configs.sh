#!/bin/bash -e

export ARCH=arm64
export CROSS_COMPILE=aarch64-linux-gnu-

BOARD=$1
DEFCONFIG=""
DTB=""
KERNELIMAGE=""
CHIP=""
UBOOT_DEFCONFIG=""

case ${BOARD} in
	"brainypi")
		DEFCONFIG=rockchip_linux_defconfig
		UBOOT_DEFCONFIG=rk3399-brainypi_defconfig
		DTB=rk3399-brainypi.dtb
		DTB_MAINLINE=rk3399-brainypi.dtb
		export ARCH=arm64
		export CROSS_COMPILE=aarch64-linux-gnu-
		CHIP="rk3399"
		;;
	*)
		echo "board '${BOARD}' not supported!"
		exit -1
		;;
esac
