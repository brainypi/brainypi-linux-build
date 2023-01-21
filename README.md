# Building Linux (Ubuntu) for BrainyPi 

The guide will help you compile Linux for BrainyPi. Ubuntu provides ready to use base OS to build upon, hence this guide favours Ubuntu. We plan to document builds for other Distros, but this requires help from community. Contributers are welcome!

Linux OS built from this guide are not 
1. Fully feature rich 
2. Might be missing key features 
3. Might have some issues
4. Some features might not be fully tested. 

Please take a look at [Known Issues]().

## 1. Requirements

1.  Ubuntu 20.04 Laptop/PC. (These steps have been tried and tested on Ubuntu 20.04)
2.  Minimum 10 GB of disk space.

## 2. Overview of steps

1.  [Prepare system for building Linux](#3-prepare-system-for-building-linux) 
1.  [Download source code](#4-download-source-code)
1.  [Compile Uboot, Kernel and Ubuntu](#5-compile-uboot-kernel-and-ubuntu)
    1.  [Compile Uboot](#5i-compile-uboot) 
    1.  [Compile Kernel](#5ii-compile-kernel)
    1.  [Build Ubuntu](#5iii-build-ubuntu)
1.  [Generate Ubuntu image](#6-generate-ubuntu-image)
1.  [Flashing Ubuntu image to BrainyPi](#7-flashing-ubuntu-image-to-brainypi)

## 3. Prepare system for building Linux 

1.	Install tools for building.
	```sh
	sudo apt-get update
	sudo apt-get install git
	sudo apt-get install gcc-aarch64-linux-gnu device-tree-compiler libncurses5 libncurses5-dev build-essential libssl-dev mtools flex bison
	sudo apt-get install gawk wget git-core diffstat unzip texinfo gcc-multilib build-essential chrpath socat cpio python python3 python3-pip python3-pexpect xz-utils debianutils iputils-ping libsdl1.2-dev xterm sshpass curl git subversion g++ zlib1g-dev build-essential git python rsync man-db libncurses5-dev gawk gettext unzip file libssl-dev wget bc
	sudo apt-get install bc python dosfstools qemu-user-static
	```
1.	Install toolchain.
	```sh
	wget https://releases.linaro.org/components/toolchain/binaries/7.3-2018.05/aarch64-linux-gnu/gcc-linaro-7.3.1-2018.05-x86_64_aarch64-linux-gnu.tar.xz
	sudo tar xvf gcc-linaro-7.3.1-2018.05-x86_64_aarch64-linux-gnu.tar.xz  -C /usr/local/
	export ARCH=arm64
	export CROSS_COMPILE=/usr/local/gcc-linaro-7.3.1-2018.05-x86_64_aarch64-linux-gnu/bin/aarch64-linux-gnu-
	export PATH=/usr/local/gcc-linaro-7.3.1-2018.05-x86_64_aarch64-linux-gnu/bin:$PATH
	```
1.	Check if toolchain is the default choice:
	```sh
	which aarch64-linux-gnu-gcc
	/usr/local/gcc-linaro-7.3.1-2018.05-x86_64_aarch64-linux-gnu/bin/aarch64-linux-gnu-gcc
	```
	
## 4. Download source code 

```sh
git clone https://github.com/brainypi/brainypi-linux-build.git
cd brainypi-linux-build
git submodule update --init --recursive
```

## 5. Compile Uboot, Kernel and Ubuntu

### 5.i Compile Uboot

1.	Compile u-boot
	```sh
	cd u-boot 
	make rk3399-brainypi_defconfig
	make -j$(nproc)
	cd ../
	./build/mk-uboot.sh brainypi
	```
1.	The compiled artifacts will be copied to out/u-boot folder
	```sh
	ls out/u-boot/
	idbloader.img  rk3399_loader_v1.20.119.bin  spi  trust.img  uboot.img
	```
### 5.ii Compile Kernel

1.	Compile kernel without any changes to configuration.
	```sh
	./build/mk-kernel.sh brainypi
	```

1.  Compile kernel with changes to configuration 
    1.  Load default configuration
        ```sh
        make rockchip_linux_defconfig
        ```
    1.  Make changes to configuration
        ```sh
        make menuconfig 
        ```
    1.	Save configuration and copy as default configuration
        ```sh
        make savedefconfig
        cp defconfig arch/arm64/configs/rockchip_linux_defconfig
        cd ../
        ```

    1.  Build kernel 
    	```sh
        ./build/mk-kernel.sh brainypi
        ```
        
1.	The compiled artifacts will be copied to folder `out/kernel`
	```sh
	ls out/kernel/
	Image  rk3399-brainypi.dtb 
	```

### 5.iii Build Ubuntu

1.  Choose distribution and download base root filesystem
    1.  For Ubuntu 18.04
        ```sh
        wget -O rootfs.tar.gz https://cdimage.ubuntu.com/ubuntu-base/releases/18.04/release/ubuntu-base-18.04.5-base-arm64.tar.gz
        ```
    2.  For Ubuntu 20.04 
        ```sh
        wget -O rootfs.tar.gz https://cdimage.ubuntu.com/ubuntu-base/releases/20.04/release/ubuntu-base-20.04.5-base-arm64.tar.gz
        ```
    3.  For Ubuntu 22.04
        ```sh
        wget -O rootfs.tar.gz https://cdimage.ubuntu.com/ubuntu-base/releases/22.04/release/ubuntu-base-22.04.1-base-arm64.tar.gz
        ```
    
1.	Extract base root filesystem
	```sh
	mkdir rfs
	sudo tar xzvf ./rootfs.tar.gz -C ./rfs
	```

1.	Copy the kernel modules to root filesystem
	```sh
	sudo find out/rootfs/ -name build | xargs rm -rf
	sudo find out/rootfs/ -name source | xargs rm -rf
	sudo cp -arv out/rootfs/lib/* ./rfs/usr/lib/*
	```

1.	Setup chroot 
	```sh
	sudo cp -av /usr/bin/qemu-aarch64-static ./rfs/usr/bin
	sudo cp -av /run/systemd/resolve/stub-resolv.conf ./rfs/etc/resolv.conf
	sudo ./build/ch-mount.sh -m ./rfs/
	```

1.	Setup user password 
	```sh
	useradd -G sudo -m -s /bin/bash pi
	echo pi:brainy | chpasswd
	```

1.	Set hostname 
	```sh
	echo brainypi > /etc/hostname
	echo 127.0.0.1	localhost > /etc/hosts
	echo 127.0.1.1	brainypi >> /etc/hosts
	```

1.	Install basic packages
	```sh
	apt-get -y update
	apt-get -y upgrade
	apt-get -y install dialog perl locales
	```

1.	Generate locale 
	```sh
	locale-gen "en_US.UTF-8"
	```

1.	Install minimal packages
	```sh
	apt-get install -y sudo ifupdown net-tools ethtool udev wireless-tools iputils-ping resolvconf wget apt-utils wpasupplicant nano network-manager openssh-server
	```
1.	Install GUI packages
	```sh
	apt-get install -y ubuntu-desktop
	```

1.  At this stage you can install any other packages that you want to install.
	
1.	Exit chroot 
	```sh
	exit
	sudo ./build/ch-mount.sh -u ./rfs/
	```

1.	Package the rootfs 
	```sh
	sudo mv ./rfs ./binary
	sudo tar -czvf ./rfs.tar.gz ./binary
	```

## 6. Generate Ubuntu Image 

1.	Generate image for brainypi
	```sh
	./build/mk-image.sh -c rk3399 -b brainypi -t system -r ./rfs.tar.gz
	```

1.	This will combine u-boot, kernel and root filesystem into one image at location `out/system.img`

1.	`system.img` can be flashed into EMMC or into SD card using Etcher.

## 7. Flashing Ubuntu image to BrainyPi

1.  See the Flashing guides to flash ubuntu on BrainyPi
    1.  [Flash to Internal Storage (EMMC)]()
    1.  [Flash to SDcard]()

## 8. Need Help?

1.  Need help with Ubuntu compilation, Please report the problem on the forum [Link to forum](https://forum.brainypi.com/c/ubuntu/ubuntu-building/24)
1.  Facing problems with Ubuntu on BrainyPi, Please report the problem on the forum [Link to forum](https://forum.brainypi.com/c/ubuntu/23)


## 9. Known Issues
1.  Images built without GUI do not boot up to console. This is because of missing TTY config in default kernel configuration (rockchip_linux_defconfig).
2.  Bluetooth does not work. This is because the bluetooth userspace drivers are missing. 
3.  Docker does not work. This is because of missing kernel configuration for docker in default kernel configuration (rockchip_linux_defconfig).
