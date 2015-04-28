#!/bin/bash
#
# convert an Instance backed AMI into an EBS backed AMI
# http://sebastiandahlgren.se/2014/01/16/convert-an-aws-instance-store-ami-to-an-ebs-backed-ami/
# http://think-devops.blogspot.de/2013/09/convert-instance-store-ami-to-ebs.html
#
# Prerequests: 
#   - we need the the X509-cert-key-file.pem on the machine assuming under:
#        /tmp/cert/X509-cert-key-file.pem
#   - we need to export our $AWS_ACCESS_KEY and $AWS_SECRET_KEY as enironment variables like:
#       export AWS_ACCESS_KEY=your_access_key_id
#       export AWS_SECRET_KEY=your_secret_access_key
#   - we need the instance ID we want to convert $as aws_instance_id
#
#   - some commands need sudo rights
#

#######################################
## config variables
cwd=$(pwd)

## read config variables form shell script
source aws-tools.sh

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

# check ec2 tools
echo "*** Using AMI tools "$(sudo -E $EC2_HOME/bin/ec2-version)

# access key from env variable, needed for authentification
aws_access_key=$AWS_ACCESS_KEY

# secrete key from env variable, needed for authentification
aws_secret_key=$AWS_SECRET_KEY

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

# aws availability zone
aws_avail_zone=$(curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone/)

## instance id
aws_instance_id=$(curl -s http://169.254.169.254/latest/meta-data/instance-id/)

# region
aws_region=$AWS_REGION
if [[ "$aws_region" == "" ]]; then
  echo "***  ERROR: No AWS_REGION given!! "
  exit -2
fi
echo "*** Using region: $aws_region"

# architecture
aws_architecture=$AWS_ARCHITECTURE
if [[ "$aws_architecture" == "" ]]; then
  echo "*** ERROR: No AWS_ARCHITECTURE given!! "
  exit -3
fi
echo "*** Using: architechture: $aws_architecture"

# x509 cert/pk file
if [[ "$AWS_PK_PATH" == "" ]]; then
  echo "*** ERROR: X509 private key file \"$AWS_PK_PATH\" not found!! "
  exit -21
fi
if [[ "$AWS_CERT_PATH" == "" ]]; then
  echo "*** ERROR: X509 cert key file \"$AWS_CERT_PATH\" not found!! "
  exit -22
fi

# base AMI the instance was launched off, needed to get kernel, virtual. type etc
aws_ami_id=$AWS_AMI_ID
if [[ "$aws_ami_id" == "" ]]; then
  echo -n "Please type in the AMI Id to be copied:"
  read aws_ami_id
  if [[ "$aws_ami_id" == "" ]]; then
  	echo "*** ERROR: No AWS_AMI_ID given!! "
  	exit -31
  fi
  aws_ami_description=$(sudo -E $EC2_HOME/bin/ec2-describe-images --region $aws_region $aws_ami_id)
  if [[ "$aws_ami_description" == "" ]]; then
  	echo "*** ERROR: Could not find AMI $aws_ami_id "
  	exit -32
  fi
fi
export AWS_AMI_ID=$aws_ami_id
echo "*** Using AMI id :$aws_ami_id"

# descriptions
aws_snapshot_description="EBS Snapshot of "$aws_ami_id", delete after registering new EBS AMI"
date=$(date)
aws_ami_name="Ubuntu-LTS-12.04-Jenkins-Server-$(date '+%F-%H-%M-%S')"


####TODO ### check for proper S3 bucket and manifest file
# AWS S3 Bucket 
s3_bucket=$AWS_S3_BUCKET
if [[ "$s3_bucket" == "" ]]; then
  echo -n "Please type in the AWS S3 bucket:"
  read s3_bucket
fi
export AWS_S3_BUCKET=$s3_bucket
echo "*** Using AWS S3 bucket:$s3_bucket"

## manifest of the bundled AMI
manifest=$AWS_MANIFEST
if [[ "$manifest" == "" ]]; then
  echo -n "Please type in the AMI manifest file name:"
  read manifest
fi
export AWS_MANIFEST=$manifest
echo "*** Using AMI manifest:$manifest"

## get the kernel image (aki) 
source select_pvgrub_kernel.sh
echo "*** Using kernel:$AWS_KERNEL"

## install pv (pipe viewer)
sudo apt-get install -y pv

# our AWS Instance ID
current_ami_id=$(curl -s http://169.254.169.254/latest/meta-data/ami-id) 
current_instance_id=$(curl -s http://169.254.169.254/latest/meta-data/instance-id) 

## config variables
######################################
## creating ebs volume to be bundle root dev
echo "*** Creating EBS Volume"
output=$(sudo -E $EC2_HOME/bin/ec2-create-volume --size 12 --region $aws_region --availability-zone $aws_avail_zone)
echo $output
aws_volume_id=$(echo $output | cut -d ' ' -f 2)
if [[ "$aws_volume_id" == "" ]]; then
  echo "*** ERROR: No Aws Volume created!"
  exit -42
fi
echo -n "*** Using AWS Volume:$aws_volume_id. Waiting to become ready . "

######################################
## wait until volume is available
output=""
while [[ "$output" == "" ]]
do
    output=$($EC2_HOME/bin/ec2-describe-volumes --region $aws_region $aws_volume_id | grep available)
    echo -n " ."
    sleep 1
done
echo ""
$EC2_HOME/bin/ec2-create-tags $aws_volume_id  --region $aws_region --tag Name="EBS Vol: $aws_snapshot_description"

#######################################
## attach volume
echo "*** Attaching EBS Volume:$aws_volume_id"
sudo -E $EC2_HOME/bin/ec2-attach-volume $aws_volume_id -instance $current_instance_id --device $aws_ebs_device --region $aws_region
output=""
while [[ "$output" == "" ]]
do
    output=$($EC2_HOME/bin/ec2-describe-volumes --region $aws_region $aws_volume_id | grep attached)
    echo -n " ."
    sleep 1
done
echo ""
lsblk
sleep 2

#######################################
### download and unbundle instance store based AMI
echo "*** Downloading manifest $manifest from S3 bucket $s3_bucket"
sudo -E $EC2_AMITOOL_HOME/bin/ec2-download-bundle -b "$s3_bucket" -m "$manifest"  -a $AWS_ACCESS_KEY -s $AWS_SECRET_KEY --privatekey $AWS_PK_PATH -d $bundle_dir --region $aws_region

cd $bundle_dir
echo "*** Unbundling $manifest in $(pwd)"
sudo -E $EC2_AMITOOL_HOME/bin/ec2-unbundle -m $manifest --privatekey $AWS_PK_PATH 
sleep 2
######################################
## extract image name and copy image to EBS volume
image=${manifest/.manifest.xml/""}
size=$(du -sb $bundle_dir/$image | cut -f 1)
echo "*** Copying $bundle_dir/$image of size $size to $aws_ebs_device."
echo "***  This may take several minutes!"
#sudo dd if=$bundle_dir/$image | pv -s $size | sudo dd of=$aws_ebs_device bs=1M
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
