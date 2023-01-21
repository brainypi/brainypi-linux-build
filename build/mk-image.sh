#!/bin/bash -e

LOCALPATH=$(pwd)
OUT=${LOCALPATH}/out
TOOLPATH=${LOCALPATH}/rkbin/tools
EXTLINUXPATH=${LOCALPATH}/build/extlinux
CHIP=""
TARGET=""
ROOTFS_PATH=""
BOARD=""
OUTPUT_IMG="${OUT}/system.img"

PATH=$PATH:$TOOLPATH

source "$LOCALPATH"/build/partitions.sh

usage() {
    echo -e "\nUsage: build/mk-image.sh -c rk3399 -t system -r /path/to/rootfs.tar.gz \n"
    echo -e "       build/mk-image.sh -c rk3399 -t boot -b brainypi\n"
}
finish() {
    echo -e "\e[31m MAKE IMAGE FAILED.\e[0m"
    exit 1
}
trap finish ERR

OLD_OPTIND=$OPTIND
while getopts "c:t:r:b:o:h" flag; do
    case $flag in
        c)
            CHIP="$OPTARG"
            ;;
        t)
            TARGET="$OPTARG"
            ;;
        r)
            ROOTFS_PATH="$OPTARG"
            ;;
        b)
            BOARD="$OPTARG"
            ;;
        o)  OUTPUT_IMG="$OPTARG"
            ;;
        h)  usage
            ;;
        *)  usage
            ;;
    esac
done
OPTIND=$OLD_OPTIND

if [ ! -f "${EXTLINUXPATH}/${CHIP}.conf" ]; then
    CHIP="rk3288"
fi

if [ ! $CHIP ] && [ ! "$TARGET" ]; then
    usage
    exit
fi

extract_system_tar() {
    # Directory contains the target rootfs
    TARGET_ROOTFS_DIR="binary"

    if [ -e $TARGET_ROOTFS_DIR ]; then
        sudo rm -rf $TARGET_ROOTFS_DIR
    fi

    if [ ! -e ${ROOTFS_PATH} ]; then
        echo -e "\033[36mFile ${ROOTFS_PATH} not found \033[0m"
        finish
    fi
    echo -e "\033[36mExtract image \033[0m"
    sudo tar -xpf ${ROOTFS_PATH}
}

making_rfs_img() {
    TARGET_ROOTFS_DIR=./binary
    MOUNTPOINT=./rootfs
    ROOTFSIMAGE=${ROOTFS_PATH}-rootfs.img

    echo Making rootfs!

    if [ -e ${ROOTFSIMAGE} ]; then 
        rm ${ROOTFSIMAGE}
    fi
    if [ -e ${MOUNTPOINT} ]; then 
        rm -r ${MOUNTPOINT}
    fi

    # Create directories
    mkdir ${MOUNTPOINT}
    dd if=/dev/zero of=${ROOTFSIMAGE} bs=1M count=0 seek=7000

    echo Format rootfs to ext4
    mkfs.ext4 ${ROOTFSIMAGE}

    echo Mount rootfs to ${MOUNTPOINT}
    sudo mount  ${ROOTFSIMAGE} ${MOUNTPOINT}
    trap finish ERR

    echo Copy rootfs to ${MOUNTPOINT}
    sudo cp -rfp ${TARGET_ROOTFS_DIR}/*  ${MOUNTPOINT}

    echo Umount rootfs
    sudo umount ${MOUNTPOINT}

    echo Rootfs Image: ${ROOTFSIMAGE}

    e2fsck -p -f ${ROOTFSIMAGE}
    resize2fs -M ${ROOTFSIMAGE}
}

generate_boot_image() {
    BOOT=${OUT}/boot.img
    rm -rf "${BOOT}"

    echo -e "\e[36m Generate Boot image start\e[0m"

    # 500Mb
    mkfs.vfat -n "boot" -S 512 -C "${BOOT}" $((500 * 1024))

    mmd -i "${BOOT}" ::/extlinux

    if [ "${BOARD}" == "brainypi" ] ; then
        mmd -i "${BOOT}" ::/overlays
    fi

    mcopy -i "${BOOT}" -s "${EXTLINUXPATH}"/${CHIP}.conf ::/extlinux/extlinux.conf
    mcopy -i "${BOOT}" -s "${OUT}"/kernel/* ::

    echo -e "\e[36m Generate Boot image : ${BOOT} success! \e[0m"
}

generate_system_image() {
    if [ ! -f "${OUT}/boot.img" ]; then
        echo -e "\e[31m CAN'T FIND BOOT IMAGE \e[0m"
        usage
        exit
    fi

    if [ ! -f "${ROOTFS_PATH}" ]; then
        echo -e "\e[31m CAN'T FIND ROOTFS IMAGE \e[0m"
        usage
        exit
    fi
    extract_system_tar
    making_rfs_img
    rm -rf "${OUTPUT_IMG}"

    echo "Generate System image : ${OUTPUT_IMG} !"

    # last dd rootfs will extend gpt image to fit the size,
    # but this will overrite the backup table of GPT
    # will cause corruption error for GPT
    IMG_ROOTFS_SIZE=$(stat -L --format="%s" "${ROOTFS_PATH}-rootfs.img")
    GPTIMG_MIN_SIZE=$(expr "$IMG_ROOTFS_SIZE" + \( "${LOADER1_SIZE}" + "${RESERVED1_SIZE}" + "${RESERVED2_SIZE}" + "${LOADER2_SIZE}" + "${ATF_SIZE}" + "${BOOT_SIZE}" + 35 \) \* 512)
    GPT_IMAGE_SIZE=$(expr "$GPTIMG_MIN_SIZE" \/ 1024 \/ 1024 + 2)

    dd if=/dev/zero of="${OUTPUT_IMG}" bs=1M count=0 seek="$GPT_IMAGE_SIZE"

    if [ "$BOARD" == "brainypi" ]; then
        parted -s "${OUTPUT_IMG}" mklabel gpt
        parted -s "${OUTPUT_IMG}" unit s mkpart loader1 "${LOADER1_START}" $(expr "${RESERVED1_START}" - 1)
        # parted -s ${SYSTEM} unit s mkpart reserved1 ${RESERVED1_START} $(expr ${RESERVED2_START} - 1)
        # parted -s ${SYSTEM} unit s mkpart reserved2 ${RESERVED2_START} $(expr ${LOADER2_START} - 1)
        parted -s "${OUTPUT_IMG}" unit s mkpart loader2 "${LOADER2_START}" $(expr "${ATF_START}" - 1)
        parted -s "${OUTPUT_IMG}" unit s mkpart trust "${ATF_START}" $(expr "${BOOT_START}" - 1)
        parted -s "${OUTPUT_IMG}" unit s mkpart boot "${BOOT_START}" $(expr "${ROOTFS_START}" - 1)
        parted -s "${OUTPUT_IMG}" set 4 boot on
        parted -s "${OUTPUT_IMG}" -- unit s mkpart rootfs "${ROOTFS_START}" -34s
    else
        parted -s "${OUTPUT_IMG}" mklabel gpt
        parted -s "${OUTPUT_IMG}" unit s mkpart boot "${BOOT_START}" $(expr "${ROOTFS_START}" - 1)
        parted -s "${OUTPUT_IMG}" set 1 boot on
        parted -s "${OUTPUT_IMG}" -- unit s mkpart rootfs "${ROOTFS_START}" -34s
    fi

    if [ "$CHIP" == "rk3328" ] || [ "$CHIP" == "rk3399" ] || [ "$CHIP" == "rk3399pro" ]; then
        ROOT_UUID="614e0000-0000-4b53-8000-1d28000054a9"
    elif [ "$CHIP" == "rk3308" ] || [ "$CHIP" == "px30" ]; then
        ROOT_UUID="614e0000-0000-4b53-8000-1d28000054a9"
    else
        ROOT_UUID="614e0000-0000-4b53-8000-1d28000054a9"
    fi

    if [ "$BOARD" == "brainypi" ]; then
        gdisk "${OUTPUT_IMG}" <<EOF
x
c
5
${ROOT_UUID}
w
y
EOF
    else
        gdisk "${OUTPUT_IMG}" <<EOF
x
c
2
${ROOT_UUID}
w
y
EOF
    fi

    # burn u-boot
    case ${CHIP} in
    rk322x | rk3036 )
        dd if="${OUT}"/u-boot/idbloader.img of="${OUTPUT_IMG}" seek="${LOADER1_START}" conv=notrunc
        ;;
    px30 | rk3288 | rk3308 | rk3328 | rk3399 | rk3399pro )
        dd if="${OUT}"/u-boot/idbloader.img of="${OUTPUT_IMG}" seek="${LOADER1_START}" conv=notrunc
        dd if="${OUT}"/u-boot/uboot.img of="${OUTPUT_IMG}" seek="${LOADER2_START}" conv=notrunc
        dd if="${OUT}"/u-boot/trust.img of="${OUTPUT_IMG}" seek="${ATF_START}" conv=notrunc
        ;;
    *)
        ;;
    esac

    # burn boot image
    dd if="${OUT}"/boot.img of="${OUTPUT_IMG}" conv=notrunc seek="${BOOT_START}"

    # burn rootfs image
    dd if="${ROOTFS_PATH}-rootfs.img" of="${OUTPUT_IMG}" conv=notrunc,fsync seek="${ROOTFS_START}"
}

if [ "$TARGET" = "boot" ]; then
    generate_boot_image
elif [ "$TARGET" == "system" ]; then
    generate_system_image
fi
