#!/bin/bash

###############################################################################
# To all DEV around the world :)                                              #
# to build this kernel you need to be ROOT and to have bash as script loader  #
# do this:                                                                    #
# cd /bin                                                                     #
# rm -f sh                                                                    #
# ln -s bash sh                                                               #
# now go back to kernel folder and run:                                       # 
#                                                         		      #
# sh clean_kernel.sh                                                          #
#                                                                             #
# Now you can build my kernel.                                                #
# using bash will make your life easy. so it's best that way.                 #
# Have fun and update me if something nice can be added to my source.         #
###############################################################################

# Time of build startup
res1=$(date +%s.%N)

echo "${bldcya}***** Setting up Environment *****${txtrst}";

. ./env_setup.sh ${1} || exit 1;


# Generate Ramdisk
echo "${bldcya}***** Generating Ramdisk *****${txtrst}"
echo "0" > $TMPFILE;
(
# remove previous initramfs files
if [ -d $INITRAMFS_TMP ]; then
	echo "${bldcya}***** Removing old temp initramfs_source *****${txtrst}";
	rm -rf $INITRAMFS_TMP;
fi;

	mkdir -p $INITRAMFS_TMP;
	cp -ax $INITRAMFS_SOURCE/* $INITRAMFS_TMP;
	# clear git repository from tmp-initramfs
	if [ -d $INITRAMFS_TMP/.git ]; then
		rm -rf $INITRAMFS_TMP/.git;
	fi;
	
	# clear mercurial repository from tmp-initramfs
	if [ -d $INITRAMFS_TMP/.hg ]; then
		rm -rf $INITRAMFS_TMP/.hg;
	fi;

	# remove empty directory placeholders from tmp-initramfs
	find $INITRAMFS_TMP -name EMPTY_DIRECTORY | parallel rm -rf {};

	# remove more from from tmp-initramfs ...
	rm -f $INITRAMFS_TMP/update*;

	# remove old ramdisk cpio
	if [ -e $KERNELDIR/ramdisk.cpio ]; then
		rm -f $KERNELDIR/ramdisk.cpio;
	fi;
	if [ -e $KERNELDIR/ramdisk-recovery.cpio ]; then
		rm -f $KERNELDIR/ramdisk-recovery.cpio;
	fi;

	./utilities/mkbootfs $INITRAMFS_TMP/cwm-recovery > $KERNELDIR/ramdisk-recovery.cpio;
	rm -rf $INITRAMFS_TMP/cwm-recovery >> /dev/null;
	./utilities/mkbootfs $INITRAMFS_TMP > $KERNELDIR/ramdisk.cpio;

	if [ ! -s $KERNELDIR/ramdisk.cpio ] || [ ! -s $KERNELDIR/ramdisk-recovery.cpio ]; then
		echo "${bldblu}Ramdisk didn't generated properly. Terminating.${txtrst}";
		exit 1;
	fi
	echo "1" > $TMPFILE;
	echo "${bldcya}***** Ramdisk Generation Completed Successfully *****${txtrst}"
)&

if [ ! -f $KERNELDIR/.config ]; then
	echo "${bldcya}***** Writing Config *****${txtrst}";
	cp $KERNELDIR/arch/arm/configs/$KERNEL_CONFIG .config;
	make $KERNEL_CONFIG;
fi;

. $KERNELDIR/.config

# remove previous zImage files
if [ -e $KERNELDIR/zImage ]; then
	rm $KERNELDIR/zImage;
	rm $KERNELDIR/boot.img;
fi;
if [ -e $KERNELDIR/arch/arm/boot/zImage ]; then
	rm $KERNELDIR/arch/arm/boot/zImage;
fi;

# remove previous initramfs files
rm -rf $KERNELDIR/out/system/lib/modules >> /dev/null;
rm -rf $KERNELDIR/out/tmp_modules >> /dev/null;
rm -rf $KERNELDIR/out/temp >> /dev/null;

# clean initramfs old compile data
rm -f $KERNELDIR/usr/initramfs_data.cpio >> /dev/null;
rm -f $KERNELDIR/usr/initramfs_data.o >> /dev/null;

# remove all old modules before compile
find $KERNELDIR -name "*.ko" | parallel rm -rf {};

mkdir -p $KERNELDIR/out/system/lib/modules
mkdir -p $KERNELDIR/out/tmp_modules

# make modules and install
echo "${bldcya}***** Compiling modules *****${txtrst}"
if [ $USER != "root" ]; then
	make -j$NUMBEROFCPUS modules || exit 1
else
	nice -n -15 make -j$NUMBEROFCPUS modules || exit 1
fi;

echo "${bldcya}***** Installing modules *****${txtrst}"
if [ $USER != "root" ]; then
	make -j$NUMBEROFCPUS INSTALL_MOD_PATH=$KERNELDIR/out/tmp_modules modules_install || exit 1
else
	nice -n -15 make -j$NUMBEROFCPUS INSTALL_MOD_PATH=$KERNELDIR/out/tmp_modules modules_install || exit 1
fi;

# copy modules
echo "${bldcya}***** Copying modules *****${txtrst}"
find $KERNELDIR/out/tmp_modules -name '*.ko' | parallel cp -av {} $KERNELDIR/out/system/lib/modules;
find $KERNELDIR/out/system/lib/modules -name '*.ko' | parallel ${CROSS_COMPILE}strip --strip-debug {};
chmod 755 $KERNELDIR/out/system/lib/modules/*;

# remove temp module files generated during compile
echo "${bldcya}***** Removing temp module stage 2 files *****${txtrst}"
rm -rf $KERNELDIR/out/tmp_modules >> /dev/null

# wait for the successful ramdisk generation
while [ $(cat ${TMPFILE}) == 0 ]; do
	sleep 2;
	echo "${bldblu}Waiting for Ramdisk generation completion.${txtrst}";
done;

# make zImage
echo "${bldcya}***** Compiling kernel *****${txtrst}"
if [ $USER != "root" ]; then
	make -j$NUMBEROFCPUS zImage
else
	nice -n -15 make -j$NUMBEROFCPUS zImage
fi;

if [ -e $KERNELDIR/arch/arm/boot/zImage ]; then
	echo "${bldcya}***** Final Touch for Kernel *****${txtrst}"
	cp $KERNELDIR/arch/arm/boot/zImage $KERNELDIR/zImage;
	stat $KERNELDIR/zImage || exit 1;
	./utilities/acp -fp zImage boot.img
	# copy all needed to out kernel folder
	rm $KERNELDIR/out/boot.img >> /dev/null;
	rm $KERNELDIR/out/NeatKernel_* >> /dev/null;
	GETVER=`grep 'NeatKernel_v.*' arch/arm/configs/${KERNEL_CONFIG} | sed 's/.*_.//g' | sed 's/".*//g'`
	cp $KERNELDIR/boot.img /$KERNELDIR/out/
	cd $KERNELDIR/out/
	zip -r NeatKernel_v${GETVER}-`date +"[%m-%d]-[%H-%M]"`.zip .
	cd $KERNELDIR
        tar cvf `echo NeatKernel`.tar zImage
        cp $KERNELDIR/NeatKernel.tar /$KERNELDIR/out/
	echo "${bldcya}***** Ready to Roar *****${txtrst}";
	# finished? get elapsed time
	res2=$(date +%s.%N)
	echo "${bldgrn}Total time elapsed: ${txtrst}${grn}$(echo "($res2 - $res1) / 60"|bc ) minutes ($(echo "$res2 - $res1"|bc ) seconds) ${txtrst}";	
else
	echo "${bldred}Kernel STUCK in BUILD!${txtrst}"
fi;

