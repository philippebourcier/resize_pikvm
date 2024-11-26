#!/bin/bash

# In case you run the script twice...
rm -f pikvm.img
cp v3-hdmi-rpi4-box-latest.img pikvm.img
losetup -d /dev/loop0
losetup -P /dev/loop0 pikvm.img

set -e  # Now exit on any error

# Create mount point if it doesn't exist
mkdir -p /mnt/tmp

echo "Step 1: Trimming filesystems..."
# Trim partition 3
mount /dev/loop0p3 /mnt/tmp
fstrim -v /mnt/tmp
umount /mnt/tmp

# Trim partition 4
mount /dev/loop0p4 /mnt/tmp
fstrim -v /mnt/tmp
umount /mnt/tmp

echo "Step 2: Resizing filesystems first..."
# Calculate new sizes in blocks (block size is typically 4096 bytes)
# For 5GB partition: 5*1024*1024*1024/4096 = 1310720 blocks
# For 500MB partition: 500*1024*1024/4096 = 131072 blocks

echo "Resizing partition 3 filesystem to 5GB... (for 3.6G used)"
e2fsck -f /dev/loop0p3
resize2fs /dev/loop0p3 1310720

echo "Resizing partition 4 filesystem to 500MB..."
e2fsck -f /dev/loop0p4
resize2fs /dev/loop0p4 131072

echo "Step 3: Resizing partitions..."
# Calculate new end sector for 500MB partition (500MB = 1024*1024/512 = 1048576 sectors)
parted -s /dev/loop0 unit s \
  rm 4 \
  rm 3 \
  mkpart primary 1048576s 11534335s \
  mkpart primary 13631488s 14680063s  # End = start + 1048576 - 1

# Wait a moment for the kernel to update partition table
partprobe /dev/loop0
sleep 2

echo "Step 4: Verifying new filesystem sizes..."
e2fsck -f /dev/loop0p3
e2fsck -f /dev/loop0p4

echo "Step 5: Final partition layout:"
parted -s /dev/loop0 unit s print

echo "Step 6: Calculating final image size..."
# Use the end of partition 4 plus some padding
TOTAL_BYTES=$((14680063 * 512 + 1048576))  # End sector * sector size + 1MB padding
echo "New size will be: $((TOTAL_BYTES/1024/1024)) MB"

# Detach the loop device
echo "Step 7: Detaching loop device..."
losetup -d /dev/loop0

# Truncate the image
echo "Step 8: Resizing the image file..."
truncate --size=$TOTAL_BYTES pikvm.img

echo "Process complete!"
echo "You can verify the result by remounting the image:"
echo "losetup -P /dev/loop0 pikvm.img"
echo "lsblk"
