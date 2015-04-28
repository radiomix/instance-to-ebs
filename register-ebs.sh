#!/bin/bash
# Bundle Instance backed AMI, which was configured, to be registered as a new EBS backed AMI
#  http://docs.aws.amazon.com/AWSEC2/latest/UserGuide/creating-an-ami-instance-store.htm
#
# Prerequisite:
#    THE FOLLOWING IS USUMED:
#   - X509-cert-key-file.pem on the machine assuming under: /tmp/cert/, file path will be exported as AWS_CERT_PATH
#   - X509-pk-key-file.pem on the machine assuming under: /tmp/cert/, file path will be exported as AWS_PK_PATH
#   - AWS_ACCESS_KEY, AWS_SECRET_KEY and AWS_ACCOUNT_ID as enironment variables 
#   - AWS API/AMI tools installed and in $PATH
########## ALL THIS IS DONE BY SCRIPT prepare-aws-tools.sh ###################
#   - we need the instance ID we want to convert $as aws_instance_id
#   - some commands need sudo rights
# What we do
#   - install grub legacy version 0.9x or smaller
#   - install gdisk, kpartx to partition
#   - adjust kernel command line parameters in /boot/grub/menu.lst
#   - bundle the AMI locally (is there enough space on this machine?)
#   - upload the AMI
#   - register the AMI
#   - delete the local bundle

#######################################
## config variables

cwd=$(pwd)

## read config variables form shell script
source aws-tools.sh

# ami descriptions and ami name
aws_ami_description="Intermediate AMI snapshot, for backup-reasons"
date_fmt=$(date '+%F-%H-%M-%S')
string=$(grep ID /etc/lsb-release)
id=${string##*=}
string=$(grep RELEASE /etc/lsb-release)
release=${string##*=}
aws_ami_name="jenkinspoc-$id-$release-bundle-instance-$date_fmt"

# bundle directory, should be on a partition with lots of space
bundle_dir="/mnt/ami-bundle/"
if [[ ! -d $bundle_dir ]]; then
  sudo mkdir $bundle_dir
fi
result=$(sudo test -w $bundle_dir && echo yes)
if [[ $result != yes ]]; then
  echo " ERROR: directory $bundle_dir to bundle the image is not writable!! "
  exit -11
fi

# read AWS S3 Bucket from env variable and concat date
s3_bucket="elemica-jenkinspoc/ami-bundle/$date_fmt"
echo -n "Type in your AWS_S3_BUCKET or <ENTER> for \"$s3_bucket\""
read input
if  [[ "$input" == "" ]]; then
    export AWS_S3_BUCKET="$s3_bucket"
else
    export AWS_S3_BUCKET="$input"
fi
## TODO check for double slahes!
s3_bucket="$AWS_S3_BUCKET"

# image file prefix
prefix="bundle-instance-"$date_fmt

# access key from env variable, needed for authentification
aws_access_key=$AWS_ACCESS_KEY

# secrete key from env variable, needed for authentification
aws_secret_key=$AWS_SECRET_KEY

# region
aws_region=$AWS_REGION
if [[ "$aws_region" == "" ]]; then
  echo " ERROR: No AWS_REGION given!! "
  exit -2
fi
echo "Using region:$aws_region"

# architecture
aws_architecture=$AWS_ARCHITECTURE
if [[ "$aws_architecture" == "" ]]; then
  echo " ERROR: No AWS_ARCHITECTURE given!! "
  exit -3
fi
echo "Using architecture:$aws_architecture"

# x509 cert/pk file
if [[ "$AWS_CERT_PATH" == "" ]]; then
  echo " ERROR: X509 cert key file \"$AWS_CERT_PATH\" not found!! "
  exit -22
else
  export  AWS_CERT_PATH=$AWS_CERT_PATH
fi
if [[ "$AWS_PK_PATH" == "" ]]; then
  echo " ERROR: X509 private key file \"$AWS_PK_PATH\" not found!! "
  exit -21
else 
  export AWS_PK_PATH=$AWS_PK_PATH
fi

# AMI id we are bundling (This one!)
current_ami_id=$(curl -s http://169.254.169.254/latest/meta-data/ami-id) 

# aws availability zone
aws_avail_zone=$(curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone/)

## instance id
aws_instance_id=$(curl -s http://169.254.169.254/latest/meta-data/instance-id/)

# descriptions
aws_snapshot_description="AMI "$current_ami_id=", delete after registering new EBS AMI"
date=$(date)
aws_ami_name="Ubuntu-LTS-12.04-Jenkins-Server-$(date '+%F-%H-%M-%S')"


# log file
log_file=bundle-$date_fmt.log
touch $log_file

## end config variables
######################################


######################################
echo "*** Bundling AMI:$current_ami_id:"$output
echo "*** Bundling AMI:$current_ami_id:"$output >> $log_file

## packages needed anyways
echo "*** Installing packages 'gdisk kpartx'"
sudo apt-get update
sudo apt-get install -y gdisk kpartx 

#######################################
## check grub version, we need grub legacy
echo  "*** Installing grub verions 0.9x"
sudo grub-install --version
sudo apt-get install -y grub
grub_version=$(grub --version)
echo "*** Grub version:$grub_version."

#######################################
## find root device to check grub version
echo "*** Checking root device"
mount | grep sda
lsblk  #not on all distros available
### read the root device
echo -n "Enter the root device: /dev/"
read _device
root_device="/dev/$_device"
## check for root defice
#sudo fdisk -l $root_device
sudo file -s $root_device | grep "part /$"

#######################################
### show boot cmdline parameter and adjust /boot/grub/menu.lst
echo "*** Checking for boot parameters"
echo ""
echo "*** Next line holds BOOT COMMAND LINE PARAMETERS:"
cat /proc/cmdline
echo "*** Next line holds KERNEL PARAMETERS in /boot/grub/menu.lst:"
grep ^kernel /boot/grub/menu.lst 
echo
echo  "If first entry differs from BOOT COMMAND LINE PARAMETER, please edit /boot/grub/menu.list "
echo -n "Do you want to edit /boot/grub/menu.list to reflect command line? [y|N]:"
read edit
if  [[ "$edit" == "y" ]]; then
  sudo vi /boot/grub/menu.lst
fi

#######################################
### remove evi entries in /etc/fstab if exist
echo "*** Checking for efi/uefi partitions in /etc/fstab"
efi=$(grep -i efi /etc/fstab)
if [[ "$efi" != "" ]]; then
  echo "Please delete these UEFI/EFI partition entries \"$efi\" in /etc/fstab"
  read -t 20
  sudo vi /etc/fstab
fi

#######################################
### what virtualization type are we?
### we check curl -s http://169.254.169.254/latest/meta-data/profile/
### returning [default-paravirtual|default-hvm]
meta_data_profile=$(curl -s http://169.254.169.254/latest/meta-data/profile/ | grep "default-")
profile=${meta_data_profile##default-}
### used in ec2-bundle-volume
virtual_type="--virtualization-type "$profile" "
aws_ami_name=$aws_ami_name"-"$profile

echo "*** Found virtualization type $profile"
## on paravirtual AMI every thing is fine here
partition=""
## for hvm AMI we set partition mbr
if  [[ "$profile" == "hvm" ]]; then
  partition="  --partition mbr "
fi

#######################################
### do we need --block-device-mapping for ec2-bundle-volume ?
echo -n "Do you want to bundle with parameter \"--block-device-mapping \"? [y|N]:"
read blockDevice
if  [[ "$blockDevice" == "y" ]]; then
  echo "Root device is set to \"$root_device\". Select root device [xvda|sda] in device mapping:[x|S]"
  read blockDevice
  if  [[ "$blockDevice" == "x" ]]; then
    blockDevice="  --block-device-mapping ami=xvda,root=/dev/xvda1 "
  else
    blockDevice="  --block-device-mapping ami=sda,root=/dev/sda1 "
  fi
else
    blockDevice=""
fi


#######################################
# bundle directory
bundle_dir="/tmp/bundle"
if [[ ! -d $bundle_dir ]]; then
  sudo mkdir $bundle_dir
fi
# check if writable
result=$(sudo test -w $bundle_dir && echo yes)
if [[ $result != yes ]]; then
  echo "*** ERROR: directory $bundle_dir to bundle the image is not writable!! "
  exit -11
fi

#######################################
# device and mountpoint of the new volume; 
# we put our new AMI onto this device(aws_volume)
aws_ebs_device=/dev/xvdi
lsblk
echo    "Chose device to mount EBS volume. If $aws_ebs_device is not listed, type <ENTER>"
echo -n "Else add letters to /dev/xvd"
read letter
if [[ "$letter" != "" ]]; then
    aws_ebs_device=/dev/xvd$letter
fi
echo "*** Using device:$aws_ebs_device"

aws_ebs_mount_point=/mnt/ebs
if [[ ! -d $aws_ebs_mount_point ]]; then
  sudo mkdir $aws_ebs_mount_point
fi
result=$(sudo test -w $aws_ebs_mount_point && echo yes)
if [[ $result != yes ]]; then
  echo "***  ERROR: directory $aws_ebs_mount_point to mount the image is not writable!! "
  exit -12
fi

#######################################
ec2_version=$(sudo -E $EC2_HOME/bin/ec2-version)
log_message="
*** Using partition:$partition 
*** Using virtual_type:$virtual_type
*** Using block_device:$blockDevice
*** Using s3_bucket:$s3_bucket
*** Using EC2 version:$ec2_version"
## write output to log file
echo  "$log_message"
echo  "$log_message" >> $log_file
sleep 5
start=$SECONDS

######################################
## creating ebs volume to be bundle root dev
echo "*** Creating EBS Volume to bundle"
output=$(sudo -E $EC2_HOME/bin/ec2-create-volume --size 12 --region $aws_region --availability-zone $aws_avail_zone)
echo $output
aws_bundle_volume_id=$(echo $output | cut -d ' ' -f 2)
if [[ "$aws_bundle_volume_id" == "" ]]; then
  echo "*** ERROR: No Aws Volume created!"
  exit -42
fi
echo -n "*** Using AWS Volume:$aws_bundle_volume_id. Waiting to become ready . "

######################################
## wait until volume is available
output=""
while [[ "$output" == "" ]]
do
    output=$($EC2_HOME/bin/ec2-describe-volumes --region $aws_region $aws_bundle_volume_id | grep available)
    echo -n " ."
    sleep 1
done
echo ""
$EC2_HOME/bin/ec2-create-tags $aws_bundle_volume_id  --region $aws_region --tag Name="EBS Vol: $aws_snapshot_description"

#######################################
## attach volume
echo "*** Attaching EBS Volume:$aws_bundle_volume_id"
sudo -E $EC2_HOME/bin/ec2-attach-volume $aws_bundle_volume_id -instance $current_instance_id --device $aws_ebs_device --region $aws_region
output=""
while [[ "$output" == "" ]]
do
    output=$($EC2_HOME/bin/ec2-describe-volumes --region $aws_region $aws_bundle_volume_id | grep attached)
    echo -n " ."
    sleep 1
done
echo ""
lsblk
sleep 2

echo "NEXT STEP BUNDLING" && exit


#######################################
### this is bundle-work
### we write the command string to $log_file and execute it 
sleep 2
#######################################
echo "*** Bundleing AMI, this may take several minutes "
bundle_command="sudo -E $EC2_AMITOOL_HOME/bin/ec2-bundle-vol -k $AWS_PK_PATH -c $AWS_CERT_PATH -u $AWS_ACCOUNT_ID -r x86_64 -e /tmp/cert/ -d $bundle_dir -p $prefix  $blockDevice $partition --batch"
echo $bundle_command >> $log_file
$bundle_command
sleep 2



export AWS_S3_BUCKER=$s3_bucket
export AWS_MANIFEST=$prefix.manifest.xml

## manifest of the bundled AMI
manifest=$AWS_MANIFEST

## get the kernel image (aki) 
source select_pvgrub_kernel.sh
echo "*** Using kernel:$AWS_KERNEL"

## profiling
end=$SECONDS
period=$(($end - $start))
log_message="***  
*** PARAMETER USED:
*** Root device:$root_device
*** Grub version:$(grub --version)
*** Bundle folder:$bundle_dir
*** Block device mapping:$blockDevice
*** Partition flag:$partition
*** Virtualization:$virtual_type
*** S3 Bucket:$s3_bucket
*** Manifest:$prefix.manifest.xml
*** Region:$aws_region
***
*** Bundled AMI:$current_ami_id in $period seconds"

## write log message to stdout and to log file
echo "$log_message"
echo "$log_message" >> $log_file


######################################
## extract image name and copy image to EBS volume
image=${manifest/.manifest.xml/""}
size=$(du -sb $bundle_dir/$image | cut -f 1)
echo "*** Copying $bundle_dir/$image of size $size to $aws_ebs_device."
echo "***  This may take several minutes!"
sudo dd if=$bundle_dir/$image of=$aws_ebs_device bs=1M
echo "*** Checking partition $aws_ebs_device"
sudo partprobe $aws_ebs_device

######################################
## check /etc/fstab on EBS volume
## mount EBS volume
sudo mount -o rw $aws_ebs_device $aws_ebs_mount_point
## edit /etc/fstab to remove ephimeral partitions
ephimeral=$(grep ephimeral $aws_ebs_mount_point/etc/fstab)
if [[ "$ephimeral" != "" ]]; then
    echo "Edit $aws_ebs_mount_point/etc/fstab to remove ephimeral partitions"
    sleep 5
    sudo vi $aws_ebs_mount_point/etc/fstab
fi
# unmount EBS volume
sudo umount $aws_ebs_device

#######################################
## create a snapshot and verify it
echo "*** Creating Snapshot from Volume:$aws_volume_id."
echo "*** This may take several minutes"
output=$($EC2_HOME/bin/ec2-create-snapshot $aws_volume_id --region $aws_region -d "$aws_snapshot_description" -O $AWS_ACCESS_KEY -W $AWS_SECRET_KEY )
aws_snapshot_id=$(echo $output | cut -d ' ' -f 2)
echo $output
echo -n "*** Using snapshot:$aws_snapshot_id. Waiting to become ready . "

#######################################
## wait until snapshot is compleeted
completed=""
while [[ "$completed" == "" ]]
do
    completed=$($EC2_HOME/bin/ec2-describe-snapshots $aws_snapshot_id --region $aws_region | grep completed)
    echo -n ". "
    sleep 3
done
echo ""

#######################################
## register a new AMI from the snapshot
output=$($EC2_HOME/bin/ec2-register -O $AWS_ACCESS_KEY -W $AWS_SECRET_KEY --region $aws_region -n "$aws_ami_name" -s $aws_snapshot_id -a $AWS_ARCHITECTURE --kernel $AWS_KERNEL)
echo $output
aws_registerd_ami_id=$(echo $output | cut -d ' ' -f 2)
echo "*** Registerd new AMI:$aws_registerd_ami_id"

######################################
## unmount and detach EBS volume
echo "*** Detaching EBS Volume:$aws_volume_id"
$EC2_HOME/bin/ec2-detach-volume $aws_volume_id --region $aws_region -O $AWS_ACCESS_KEY -W $AWS_SECRET_KEY

#######################################
## and delete the volume and remove bundle-files
echo "*** Please delete EBS Volume:$aws_volume_id"
#$EC2_HOME/bin/ec2-delete-volume $aws_volume_id  -O $AWS_ACCESS_KEY -W $AWS_SECRET_KEY
echo "*** Deleting EBS Volume:$aws_volume_id"
sudo rm -rf $bundle_dir/*
#######################################
cd $cwd
echo "*** Finished! Created AMI: $aws_registerd_ami_id ***"
