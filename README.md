# instance-to-ebs
Copy an Instance Backed AMI into an EBS Backed AMI
Goal
----

### Files
 + [`aws-tools.sh`](aws-tools.sh) Installs `ec2-api-tools` and `ec2-ami-tools` and 
packages `ruby`, `unzip`, `wget` and `openssl`, checks for Java installatation and 
asks to install `default-jre`, exports env variables for AWS credentials.
 + [`bundle-instance.sh`](bundle-instance.sh)
  - installs packages `gdisk`,`kpartx` and `grub` (legacy)
  - checks for command line kernel parameters and its counterpart in `/boot/grub/menu.lst` and edit them
  - checks for `efi` partitions in `/etc/fstab`
  - check the proper virtualization type with `curl -s http://169.254.169.254/latest/meta-data/profile/ | grep "default-"` 
returning [default-paravirtual|default-hvm] and set bundle parameters
  - bundles and uploads the image and registers an AMI
 + [`convert-instance-to-ebs.sh`](convert-instance-to-ebs.sh)
  - checks for AWS environment variables
  - creates and attaches an EBS volume
  - dowloads and unbundles the previous manifest
  - creates a snapshot and registers an AMI
  - unmounts and dettaches the EBS volume

### Prerequisites
-------------
`aws-stools.sh` reads and exports some environment variables:

#### AWS
 + `AWS_ACCESS_KEY="MY-ACCESS-KEY"`
 + `AWS_SECRET_KEY="My-Secret-Key"`
 + `AWS_ACCOUNT_ID="My-Account-Id"`
 + `AWS_REGION="My-Region"`
 + `AWS_ARCHITECTURE=" i386 | x86_6"`
 + `AWS_CERT_PATH="/path/to/my/x509-cert.pem"`
 + `AWS_PK_PATH="/path/to/my/x509-pk.pem"`

#### EC2
 + `EC2_AMITOOL_HOME=$ami_tool`
 + `EC2_HOME=$api_tool`
 + `PATH=$PATH:$EC2_AMITOOL_HOME/bin:$EC2_HOME/bin`

#### JAVA
`ec2-register` is a EC2 CLI Tool written in Java and thus needs Java
installed.
 + `JAVA_HOME=$java_home`

#### X.509 Cert and Private Key
EC2 commands partly use an X.509 certificate -even self signed- to
encrypt communication. You can either generate these files from the AWS
console under _Security Credentials_ or generate them by hand, after
openssl installation. To generate and self sign a certificate valid for
10 years in 2048 bit type:
```bash
openssl genrsa 2048 > private-key.pem
penssl req -new -x509 -nodes -sha1 -days 3650 -key private-key.pem -outform PEM > certificate.pem
```
The second step asks for information included in the certificate. You
can use the default or input your data.
The Certificate has to be uploaded to the AWS console, showing a thumbprint. It is 
usefull to rename the cert and key file to reflect the thumbprint. 
Both cert and private key have to be uploaded to the instance, before bundling it.

### Processes to stop
To bundle an instance, all programs writing to root device have to be
stopped and restarted:
 + /etc/rc2.d/jenkins
 + /etc/rc2.d/rabbitmq-server
 + /etc/rc2.d/redis-server
 + /etc/rc2.d/jpdm
 + erlang process `epmd` by hand

### Usage
#### Bundling an Instance backed AMI
To bundle and register an Instance backed AMI, run the two shell scripts:
```
$source aws-tools.sh
$source bundle_intance.sh
```
Save the log file `bundle-2015-04-24-10-37-19.log` to remeber AWS
parameters. 
We recommend the following parameter during a `bundle_instance.sh` run:

**virtualization type `paravirtual`**
 * _Is virtualization type:hvm correct?_ **YES**
 * _`--block-device-mapping`_ **NO**

**virtualization type `hvm`**
 * _Is virtualization type:hvm correct?_ **YES**
 * _`--block-device-mapping`_  **YES**
 * _Select root device [xvda|sda] in device mapping_ **SDA**

#### Convert an Instance backed AMI into an EBS backed AMI
To unbundle the Instance backed AMI and register an EBS backed AMI, you need
the log file containing the AWS paramter of the previous run at hand.
Then run the two shell scripts:
```
$source aws-tools.sh
$source convert-instance-to-ebs.sh
```


## AMIs

As source AMIs we use two Ubuntu LTS Server AMIs
 + [ubuntu-precise-12.04-amd64-server](http://thecloudmarket.com/image/ami-a7785897--ubuntu-images-hvm-instance-ubuntu-precise-12-04-amd64-server-20150227) 
an Ubuntu 12.04 LTS Server x86_64 AMI, instance store for region us-west-2 
 + [ubuntu-trusty-14.04-amd64-server](http://thecloudmarket.com/image/ami-29ebb519--ubuntu-images-hvm-ssd-ubuntu-trusty-14-04-amd64-server-20150123) 
an Ubuntu 14.04 LTS Server x86_64 AMI, instance store for region us-west-2 

The following AMIs have been successfully bundled and registered:
- ami-75755545 Ubuntu 12.04, amd64, instance-store, aki-fc8f11cc
- ami-a7785897 Ubuntu 12.04, amd64, hvm;instance-store, hvm
- ami-75c09945 Ubuntu 10.04, amd64, instance-store, aki-fc8f11cc
- ami-c15379f1 Ubuntu 12.04, amd64, instance-store, aki-fc8f11cc

### Bundling the Instance stored into a new Instance stored AMI
The [AWS docu]( http://docs.aws.amazon.com/AWSEC2/latest/UserGuide/creating-an-ami-instance-store.htm) 
describes how to create and copy an instance stored AMI. We split the
task in two: First we install the AWS tools and check for AWS
credentials. 

## EBS vs Instance store
| Characteristics | EBS stored | Instance store stored |
|---|---|---|
|boot  | < 1 min  | < 5 min   |
|persitence  | gets replicated, persists after the instance  | persists only during live of the instance  |
|upgrading  | type,kernel,ram disk, user-data can be changes while instance is stopped  | attributes are fixed   |
|charges  | per instance usage, EBS and snapshot storage | per usage and S3 storage   |
|AMI creation/bundling  | single command/call  | installation of AMI tools  |
|**stopped state**  | **root volume persists while instance is stopped** |  **cannot be stopped, instance runs or terminates (data loss)**  |

#### Issues 
 - If `ec2-bundle-vol` throws error `ec2/amitools/crypto.rb:13:in
 'require': no such file to load -- openssl (LoadError)`, install package 'ruby-full'.
 - If `ec2-upload-bundle` throws error `Signature version 4
   authentication failed, trying different signature version
ERROR: Error talking to S3: Server.NotImplemented(501): A header you
provided implies functionality that is not implemented
` we are not allowed to write to the AWS S3 bucket. Chek S3 Bucket
settings in `bundle-instance.sh`.
 - On Ubuntu EOL(10.10, . . .), required packages can not be installed.
