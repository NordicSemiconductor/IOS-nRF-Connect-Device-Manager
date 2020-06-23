#!/bin/zsh

# Configuration

# Specify the board
BOARD=nrf52dk_nrf52832

# Script

## West update
# (cd ~/zephyrproject && exec west update)

echo "\e[32mBuilding McuBoot for $BUILD (without Downgrade Prevention)\e[0"

# Remove build folder
(cd ~/zephyrproject/bootloader/mcuboot/boot/zephyr && exec rm -R build)

# Build mcumgr without Downgrade protection
(cd ~/zephyrproject/bootloader/mcuboot/boot/zephyr && exec west build -p auto -b $BOARD)

# Copy here
cp ~/zephyrproject/bootloader/mcuboot/boot/zephyr/build/zephyr/zephyr.hex mcuboot.hex

# (cd ~/zephyrproject/bootloader/mcuboot/boot/zephyr && exec rm -R build)

echo "\e[32mBuilding McuBoot for $BUILD (with Downgrade Prevention)\e[0"

# Remove build folder
(cd ~/zephyrproject/bootloader/mcuboot/boot/zephyr && exec rm -R build)

# Build mcumgr with Downgrade Protection
(cd ~/zephyrproject/bootloader/mcuboot/boot/zephyr && exec west build -p auto -b $BOARD -- -DCONFIG_BOOT_UPGRADE_ONLY=y -DCONFIG_BOOT_SWAP_USING_MOVE=n -DCONFIG_MCUBOOT_DOWNGRADE_PREVENTION=y)

# Copy here
cp ~/zephyrproject/bootloader/mcuboot/boot/zephyr/build/zephyr/zephyr.hex mcuboot_dp.hex

echo "\e[32mBuilding SMP Server app\e[0"

# Remove build folder
(cd ~/zephyrproject/zephyr/samples/subsys/mgmt/mcumgr/smp_svr && exec rm -R build)

# Build SMP Server app
(cd ~/zephyrproject/zephyr/samples/subsys/mgmt/mcumgr/smp_svr && exec west build -p auto -b $BOARD -- -DOVERLAY_CONFIG=overlay-bt.conf)

# Sign the app
(cd ~/zephyrproject/zephyr/samples/subsys/mgmt/mcumgr/smp_svr && exec west sign -t imgtool -- --key ~/zephyrproject/bootloader/mcuboot/root-rsa-2048.pem)

# Copy here
cp ~/zephyrproject/zephyr/samples/subsys/mgmt/mcumgr/smp_svr/build/zephyr/zephyr.signed.hex smp_svr.signed.hex

echo "\e[32mBuilding bin files\e[0"

# Sign the app
(cd ~/zephyrproject/zephyr/samples/subsys/mgmt/mcumgr/smp_svr && exec west sign -t imgtool -- --key ~/zephyrproject/bootloader/mcuboot/root-rsa-2048.pem -v 1.0.0)

# Copy here
cp ~/zephyrproject/zephyr/samples/subsys/mgmt/mcumgr/smp_svr/build/zephyr/zephyr.signed.bin smp_svr.1.0.0.signed.bin

# Sign the app
(cd ~/zephyrproject/zephyr/samples/subsys/mgmt/mcumgr/smp_svr && exec west sign -t imgtool -- --key ~/zephyrproject/bootloader/mcuboot/root-rsa-2048.pem -v 2.0.0)

# Copy here
cp ~/zephyrproject/zephyr/samples/subsys/mgmt/mcumgr/smp_svr/build/zephyr/zephyr.signed.bin smp_svr.2.0.0.signed.bin

# Sign the app
(cd ~/zephyrproject/zephyr/samples/subsys/mgmt/mcumgr/smp_svr && exec west sign -t imgtool -- --key ~/zephyrproject/bootloader/mcuboot/root-rsa-2048.pem -v 3.0.0)

# Copy here
cp ~/zephyrproject/zephyr/samples/subsys/mgmt/mcumgr/smp_svr/build/zephyr/zephyr.signed.bin smp_svr.3.0.0.signed.bin

echo "\e[32mMerging files\e[0"

mergehex -m mcuboot.hex smp_svr.signed.hex -o smp_svr.merged.hex

mergehex -m mcuboot_dp.hex smp_svr.signed.hex -o smp_svr.dp.merged.hex