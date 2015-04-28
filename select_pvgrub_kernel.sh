#!/bin/bash 
#
# get the AWS region and the architecture and select the proper PVGRUB AKI kernel
# Kernels: http://docs.aws.amazon.com/AWSEC2/latest/UserGuide/UserProvidedKernels.html#configuringGRUB
#

# Prerequisite:
# we expect the AWS_REGION and AWS_ARCHITECTURE to be exported as environment variable 
#

#############################
##
## For each reagion ther are two kernels
## one for each architecture
##
#############################
## kernel list as of March 2015  
## http://docs.aws.amazon.com/AWSEC2/latest/UserGuide/UserProvidedKernels.html#configuringGRUB
setup_x86_64() {
  kernels[ap-northeast-1]=aki-176bf516
  kernels[ap-southeast-1]=aki-503e7402
  kernels[ap-southeast-2]=aki-c362fff9
  kernels[eu-central-1]=aki-184c7a05
  kernels[eu-west-1]=aki-52a34525
  kernels[sa-east-1]=aki-5553f448
  kernels[us-east-1]=aki-919dcaf8
  kernels[us-gov-west-1]=aki-1de98d3e
  kernels[us-west-1]=aki-880531cd
  kernels[us-west-2]=aki-fc8f11cc
}

setup_i386() {
  kernels[ap-northeast-1]=aki-136bf512
  kernels[ap-southeast-1]=aki-ae3973fc
  kernels[ap-southeast-2]=aki-cd62fff7
  kernels[eu-central-1]=aki-3e4c7a23
  kernels[eu-west-1]=aki-68a3451f
  kernels[sa-east-1]=aki-5b53f446
  kernels[us-east-1]=aki-8f9dcae6
  kernels[us-gov-west-1]=aki-1fe98d3c
  kernels[us-west-1]=aki-8e0531cb
  kernels[us-west-2]=aki-f08f11c0
}

# region
aws_region=$AWS_REGION
if [[ "$aws_region" == "" ]]; then
   echo " ERROR: No AWS_REGION given!! "
   return -2
fi
echo "*** Using region: $AWS_REGION"

# architecture
aws_architecture=$AWS_ARCHITECTURE
if [[ "$aws_architecture" == "" ]]; then
    echo " ERROR: No AWS_ARCHITECTURE given!! "
    return -3
fi
echo "*** Using architecture: $AWS_ARCHITECTURE"

aws_kernel=""
declare -A kernels
if [[ "$AWS_ARCHITECTURE" == "x86_64" ]]; then
  setup_x86_64
else
  setup_i386
fi
aws_kernel=${kernels[$AWS_REGION]}
export AWS_KERNEL=$aws_kernel
echo "*** Using kernel:$AWS_KERNEL in region:$AWS_REGION for architecture:$AWS_ARCHITECTURE"

