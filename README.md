# Launch AWS EC2 Instance

Bash Script to launch EC2 Instance. This will help you to do:

 * Quick host a domain/website on EC2 Instance (including Apache2, PHP7.2 installation by default)
 * Or just launch a bare EC2 instance.




## Configuration:
By launching you get following configuration instance:
* **Instance Type** - `t2.micro`
* **Region** - `ap-south-1`
* **OS** - `Ubuntu (20.04)`
* **Labeling** - By default EC2 instance, Security group, VPC, Subnets, Route table etc are labelled with the domain/instance name. So that you can identify these easily.
* **SG Inbound Rules** - Ports enabled for instance with web hosting: 80,443,22 and for instance launched without web/domain has default port 22 enabled for public. You can later on change these from security groups.
* You get **_Elastic IP_** attached to instance
* **HTTP Server** - `Apache`
* **PHP** - `7.2` with curl, json, cgi, xsl, mbstring, fpm, common, mysql, libapache2-mod-php7.2, gd, mbstring, xml extensions



## Prerequisite
`aws cli` must be working in your system. If not, you can take help from https://aws.amazon.com/cli/
## Installation

Just download this file and run following command:
(Assuming `launch-ec2-instance.sh` is your downloaded file name.) 

Provide excexution permission:
```bash
sudo chmod ugo+x launch-ec2-instance.sh

```
Now run script

```bash
sudo sh launch-ec2-instance.sh

```
or
```bash
sudo ./launch-ec2-instance.sh

```

## Sample Output

```
-------------------------------------------
Welcome to Launch AWS EC2 instance Script
-------------------------------------------
Select your option to launch ec2 instnace (t2.micro)
1. Host domain with ec2 Instnace.
2. Just setup instnace
Enter your choice:
2
Enter instance name of your choice:
deepuser
--------------------------------------
Welcome to EC2 Instance launch script
--------------------------------------

Creating KeyPair

Key pair deepuserKey created and saved to deepuserKey.pem

Setting up VPC
Need to create new VPC
VPC created. ID: vpc-05fa348669d9234f8
Checking IGW exists...
Need to create IGW
IGW created. ID: igw-03a59ab31f7ca8e9e
Attaching it to VPC...
IGW attached to VPC

Setting up Subnets for this VPC
2 subnets created for VPC
Creating Route Table
Route Table created. ID: rtb-043da5bb2233e8d5c

Creating Public Route
Public Route created

Attaching Public Route to subnet deepuserSubAPSouth1a
Public Route attached to deepuserSubAPSouth1a


Creating Security Group...
Need to create new Security Group
Security Group created. ID: sg-0d97d47af3254a6af

Enabling port 22
Port 22 enabled

Security Group setting done.

Fetching Latest Image of Ubuntu 20.04
The image ID of the latest Ubuntu 20.04 AMI is ami-0ef82eeba2c7a0eeb

Launching EC2 instance
Instance created. ID: i-096905a09bbe273b7
Wait for the instance to be running & Both status checks are Ok
Instance ready

Naming Volumes attached to this instance

Volume ID: vol-00019ca28a34f31fb
Naming Volumes process done

Assigning Elastic IP to it
Need to allocate new Elastic IP
Elastic IP 3.111.242.78 assigned

ssh -i deepuserKey.pem ubuntu@3.111.242.78

All done. Thanks! :)
```
## Support

For support, please drop an email at ghoreladeep@gmail.com


## Authors
- [@deepghorela](https://www.github.com/deepghorela)
- [@pawanyd](https://www.github.com/pawanyd)


