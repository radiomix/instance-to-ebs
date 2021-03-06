#!/bin/bash
# Prepare an AMI with the AWS API/AMI tools
#   http://docs.aws.amazon.com/AWSEC2/latest/CommandLineReference/set-up-ec2-cli-linux.html
#   http://docs.aws.amazon.com/AWSEC2/latest/CommandLineReference/set-up-ami-tools.html
#  Prerequisites:
#   - we need ruby, unzip, wget, openssl 
#            and default-jre (for command ec2-register (CLI Tools need JAVA), thus we check for an installed version
#       http://docs.aws.amazon.com/AWSEC2/latest/CommandLineReference/set-up-ec2-cli-linux.html
#   - we need to export our $AWS_ACCESS_KEY and $AWS_SECRET_KEY as enironment variables like:
#       export AWS_ACCESS_KEY=your_access_key_id
#       export AWS_SECRET_KEY=your_secret_access_key
#   - some commands need sudo rights
#   - we need our AWS x509-pk/cert files on this machine
#
# CAUTION: to export env variables properly, this script should be sourced:
#  $:>source aws-tools.sh
#
#######################################
## config variables

## error message
declare error_msg

package_list="wget ruby unzip openssl java"

# aws credentials, may be in env variables?
aws_secret_key=$AWS_SECRET_KEY
aws_access_key=$AWS_ACCESS_KEY
aws_account_id=$AWS_ACCOUNT_ID

# region
aws_region=$AWS_REGION
if [[ "$aws_region" == "" ]]; then
  aws_zone=$(curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone)
  aws_region=${aws_zone::-1}
fi

# architecture
aws_architecture=$AWS_ARCHITECTURE

## config variables

######################################
## packages needed anyways
# We neede some packages:
for package in ${package_list}; do
  bin=$(which $package)
  if [[ "$bin" == "" ]]; then
     echo "*** ERROR: Command $package not found! Please install $package!"
     exit
 fi 
done
######################################
## install api/ami tools under /usr/local/ec2
echo "*** Installing AWS TOOLS"
prefix="/usr/local/ec2/"
sudo mkdir $prefix
sudo rm -rf $prefix/*
rm -f ec2-ami-tools.zip ec2-api-tools.zip

wget http://s3.amazonaws.com/ec2-downloads/ec2-api-tools.zip
wget http://s3.amazonaws.com/ec2-downloads/ec2-ami-tools.zip
sudo unzip -q ec2-api-tools.zip -d /usr/local/ec2/
sudo unzip -q ec2-ami-tools.zip  -d /usr/local/ec2/
rm -f ec2-ami-tools.zip ec2-api-tools.zip

######################################
# get java install path
# used by ec-tools
echo "*** SETTING JAVA PATH"
java_bin=$(which java)
if [[ "$java_bin" == "" ]]; then
    error_msg=="***  ERROR: No Java version found!"
    echo "$error_msg"
    exit
fi
java_path=$(readlink -f $java_bin)
echo $java_bin  $java_path
java_home=${java_path/'/bin/java'/''}
### set java home path
export JAVA_HOME=$java_home
echo "*** JAVA_HOME set to  \"$java_home\"" 
$JAVA_HOME/bin/java -version

######################################
### set ec2-home variable
echo "*** SETTING AWS TOOL PATH"
ami_tool=$prefix$(ls /usr/local/ec2 | grep ami)
api_tool=$prefix$(ls /usr/local/ec2 | grep api)
export EC2_AMITOOL_HOME=$ami_tool
export EC2_HOME=$api_tool
export PATH=$PATH:$EC2_AMITOOL_HOME/bin:$EC2_HOME/bin

### check if sudo ec2-path is ok:
sudo -E $EC2_HOME/bin/ec2-version
sudo -E $EC2_AMITOOL_HOME/bin/ec2-ami-tools-version

echo "*** EC2_HOME set to  \"$api_tool\""
echo "*** EC2_AMITOOL_HOME set to  \"$ami_tool\""
echo

######################################
### set the aws-access/secret-key/account-id

if [[ "$aws_access_key" == "" ]]
then
  echo -n "Enter your AWS_ACCESS_KEY:"
  read aws_access_key
fi
export AWS_ACCESS_KEY=$aws_access_key

if [[ "$aws_secret_key" == "" ]]
then
  echo -n "Enter your AWS_SECRET_KEY:"
  read aws_secret_key
fi
export AWS_SECRET_KEY=$aws_secret_key

if [[ "$aws_account_id" == "" ]]
then
  echo -n "Enter your AWS_ACCOUNT_ID:"
  read aws_account_id
fi
export AWS_ACCOUNT_ID=$aws_account_id

if [[ "$aws_region" == "" ]]; then
    echo -n "Enter your AWS_REGION:"
    read aws_region
fi
export AWS_REGION=$aws_region

if [[ "$aws_architecture" == "" ]]; then
    aws_architecture="x86_64"
fi
export AWS_ARCHITECTURE=$aws_architecture

aws_access_key=${AWS_ACCESS_KEY:0:3}********${AWS_ACCESS_KEY:${#AWS_ACCESS_KEY}-3:3}
aws_secret_key=${AWS_SECRET_KEY:0:3}********${AWS_SECRET_KEY:${#AWS_SECRET_KEY}-3:3}
aws_account_id=${AWS_ACCOUNT_ID:0:3}********${AWS_ACCOUNT_ID:${#AWS_ACCOUNT_ID}-3:3}

######################################
### set x509-pd/cert file path 
if [ -d /tmp/cert/ ]; then # may be in /tmp/cert?
   echo "Found these files in /tmp/cert/ "
   ls /tmp/cert/
fi

if [[ "$AWS_CERT_PATH" == "" ]]
then
  echo -n "Enter /path/to/x509-cert.pem: "
  read input
  if [ ! -f "$input"  ]; then
        error_msg="*** ERROR: AWS X509 CERT FILE:$input NOT FOUND!"
        echo "$error_msg"
        exit
  fi
  export AWS_CERT_PATH=$input
fi

if [[ "$AWS_PK_PATH" == "" ]]
then
  echo -n "Enter /path/to/x509-pk.pem: "
  read input
  if [  ! -f "$input" ]; then
        error_msg="*** ERROR: AWS X509 PK FILE:$input NOT FOUND!"
        echo "$error_msg"
        exit
  fi
  export AWS_PK_PATH=$input
fi

echo
echo "*** Using AWS_ACCESS_KEY:   \"$aws_access_key\""
echo "*** Using AWS_SECRET_KEY:   \"$aws_secret_key\""
echo "*** Using AWS_ACCOUNT_ID:   \"$aws_account_id\""
echo "*** Using AWS_REGION:       \"$aws_region\""
echo "*** Using AWS_ARCHITECTURE: \"$aws_architecture\""
echo "*** Using x509-cert.pem \"$AWS_CERT_PATH\""
echo "*** Using x509-pk.pem \"$AWS_PK_PATH\""

### check error messages
if [[ "$error_msg" != ""  ]]; then
  echo "************ ERROR *******************"
  echo "$error_msg"
  echo "************ ERROR *******************"
  echo "*** PLEASE REPEATE THIS STEP AGAIN!"
  unset error_msg
  exit 
fi
echo ""

