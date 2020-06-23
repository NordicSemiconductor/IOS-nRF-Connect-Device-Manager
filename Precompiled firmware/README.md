# Precompiled samples

This folder contains set of images for testing Device Manager (McuManager).

## Content

Folder name is the board name (https://docs.zephyrproject.org/latest/boards/index.html).

**build.sh** - a script used to generate files below on Mac with default paths.

**mcuboot.hex** - McuBoot bootloader.

**mcuboot_dp.hex** - McuBoot bootloader with [Downgrade Protection](https://mcuboot.com/mcuboot/design.html#downgrade-prevention) enabled.

**smp_srv.signed.hex** - [SMP Server sample](https://docs.zephyrproject.org/latest/samples/subsys/mgmt/mcumgr/smp_svr/README.html) application.

**smp_svr.merged.hex** - McuBoot with SMP Server sample, version 0.0.0. Ready to be dragged and droppen on the board.

**smp_svr.dp.merged.hex** - McuBoot with [Downgrade Protection](https://mcuboot.com/mcuboot/design.html#downgrade-prevention) enabled with SMP Server sample, version 0.0.0. Ready to be dragged and droppen on the board.

**smp_svr.1.0.0.signed.bin** - signed firmware in version 1.0.0.

**smp_svr.2.0.0.signed.bin** - signed firmware in version 2.0.0.

**smp_svr.3.0.0.signed.bin** - signed firmware in version 3.0.0.

## How to

1. Flash one of the **merged** files onto your DK.
2. Copy the last 3 files to your iCloud account, Google Drive or on the phone.
3. Open Device Manager app, go to **Image** tab, select one of the files and click Start.
4. Select desired update method. **Test and Confirm** is recommended.
5. Click Start and wait ~ 1 minute until the update is complete.
