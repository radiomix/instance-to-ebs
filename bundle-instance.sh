#!/bin/bash
# Bundle Instance backed AMI, which was configured, to be registered as a new AMI
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


# log file
log_file=bundle-$date_fmt.log
touch $log_file

# AMI id we are bundling (This one!)
current_ami_id=$(curl -s http://169.254.169.254/latest/meta-data/ami-id) 
output=$($EC2_HOME/bin/ec2-describe-images --region $aws_region $current_ami_id)

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

#######################################
### this is bundle-work
### we write the command string to $log_file and execute it 
sleep 2

echo "*** Bundleing AMI, this may take several minutes "
bundle_command="sudo -E $EC2_AMITOOL_HOME/bin/ec2-bundle-vol -k $AWS_PK_PATH -c $AWS_CERT_PATH -u $AWS_ACCOUNT_ID -r x86_64 -e /tmp/cert/ -d $bundle_dir -p $prefix  $blockDevice $partition --batch"
echo $bundle_command >> $log_file
$bundle_command
sleep 2

echo "*** Uploading AMI bundle to $s3_bucket "
upload_command="$EC2_AMITOOL_HOME/bin/ec2-upload-bundle -b $s3_bucket -m $bundle_dir/$prefix.manifest.xml -a $AWS_ACCESS_KEY -s $AWS_SECRET_KEY --region $aws_region"
echo $upload_command >> $log_file
$upload_command
sleep 2

echo "*** Registering images"
register_command="$EC2_HOME/bin/ec2-register   $s3_bucket/$prefix.manifest.xml $virtual_type -n "$aws_ami_name" -O $AWS_ACCESS_KEY -W $AWS_SECRET_KEY --region $aws_region --architecture $aws_architecture "
echo $register_command >> $log_file
output=$($register_command)
echo $output
echo $output >> $log_file
aws_ami_id=""
aws_ami_id=$(echo $output | cut -d ' ' -f 2)
sleep 2
#######################################


export AWS_AMI_ID=$aws_ami_id
export AWS_S3_BUCKER=$s3_bucket
export AWS_MANIFEST=$prefix.manifest.xml

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
*** Registerd AMI name:$aws_ami_name
*** Registerd AMI Id:$aws_ami_id
***
*** FINISHED Bundling AMI:$current_ami_id  into new AMI:$aws_ami_id in $period seconds"

## write log message to stdout and to log file
echo "$log_message"
echo "$log_message" >> $log_file
