#!/bin/bash


# Set variables for the new EC2 instance
IMAGE_ID='ami-0d5d9d301c853a04a'

# To get current logged in user.
# This will be used for changing ownership of KeyPair file.
CURRENT_USER=$(logname)

echo "-------------------------------------------\nWelcome to Launch AWS EC2 instance Script\n-------------------------------------------"
echo "Select your option to launch ec2 instnace (t2.micro)\n1. Host domain with ec2 Instnace.\n2. Just setup instnace"
echo "Enter your choice:"
read OPTION

if [ "$OPTION" = "1" ]; then
    echo 'Enter Domain Name:'
    read DOMAIN_NAME
    DEFAULT_NAME=$(echo "$DOMAIN_NAME" | sed 's/[^a-zA-Z0-9]//g')
    DOMAIN_DIR=$DEFAULT_NAME"D"
elif [ "$OPTION" = "2" ]; then
    echo 'Enter instance name of your choice:'
    read DOMAIN_NAME
    DEFAULT_NAME=$(echo "$DOMAIN_NAME" | sed 's/[^a-zA-Z0-9]//g')
    DOMAIN_DIR=$DEFAULT_NAME"D"
else
    echo 'Invalid Choice. Quiting.'
    exit
fi

EC2_INSTANCE_NAME=$DEFAULT_NAME"Inst"
INSTANCE_TYPE='t2.micro'
EIP_NAME=$DEFAULT_NAME'EIP'

KEY_NAME=$DEFAULT_NAME'Key'
REGION='ap-south-1'

VOLUME_SIZE=30
VOLUME_NAME=$DEFAULT_NAME'Vol'

# VPC Configurations
VPC_NAME=$DEFAULT_NAME"VPC"
SUBNET_CIDR_1=10.0.1.0/24
SUBNET_CIDR_2=10.0.2.0/24
SUBNET_NAME_1=$DEFAULT_NAME'SubAPSouth1a'
SUBNET_NAME_2=$DEFAULT_NAME'SubAPSouth1b'

IGW_NAME=$DEFAULT_NAME'IGW'
ROUTE_TABLE_NAME=$DEFAULT_NAME'RouteTbl'
ROUTE_NAME=$DEFAULT_NAME'RoutePub'

# Set variables for the security group
SECURITY_GROUP_NAME=$DEFAULT_NAME'Sg'
GROUP_DESCRIPTION="Security group for web traffic"
PORT_22_NAME=$DEFAULT_NAME"SSH"
PORT_80_NAME=$DEFAULT_NAME"HTTP"
PORT_443_NAME=$DEFAULT_NAME"HTTPS"

AWS_PROFILE=aws_root_spw_bytes

echo "--------------------------------------"
echo "Welcome to EC2 Instance launch script"
echo "--------------------------------------"

##########################################################
# Generate Key Pair
##########################################################
# Generate the key pair
echo ""
echo "Creating KeyPair"
# Check if the key pair already exists
EXISTS=$(aws ec2 describe-key-pairs --region $REGION --key-names $KEY_NAME --query 'KeyPairs[*].KeyName' --output text)

# If the key pair does not exist, create it
if [ -z "$EXISTS" ]; then
  aws ec2 create-key-pair --region $REGION --key-name $KEY_NAME --query 'KeyMaterial' --output text > $KEY_NAME.pem
  chmod 400 $KEY_NAME.pem
  chown $CURRENT_USER:$CURRENT_USER $KEY_NAME.pem
  echo "Key pair $KEY_NAME created and saved to $KEY_NAME.pem"
else
  echo "Key pair $KEY_NAME already exists"
fi

# Ends Generate Key Pair
##########################################################

############################################################
# Create the VPC and get its ID
echo ""
echo "Setting up VPC"
# Search for VPCs with the specified name
VPC_ID=$(aws ec2 describe-vpcs --filters "Name=tag:Name,Values=$VPC_NAME" --query "Vpcs[*].VpcId" --output text)

# Check if a VPC was found
if [ -z "$VPC_ID" ]; then
    echo "Need to create new VPC"
    VPC_ID=$(aws ec2 create-vpc --region $REGION --cidr-block 10.0.0.0/16 --instance-tenancy default --tag-specifications "ResourceType=vpc,Tags=[{Key=Name,Value=$VPC_NAME}]" --query "Vpc.VpcId" --output text)
    echo  "VPC_ID" >> log.txt
    echo  $VPC_ID >> log.txt
    echo "VPC created. ID: $VPC_ID"

    echo "Checking IGW exists..."
    EXISTS=$(aws ec2 describe-internet-gateways \
        --filters "Name=tag:Name,Values=MyIGW" \
        --query 'InternetGateways[*].InternetGatewayId' \
        --output text)

    if [ -z "$EXISTS" ]; then
        echo "Need to create IGW"
        # Create the IGW
        IGW_ID=$(aws ec2 create-internet-gateway \
            --region $REGION \
            --tag-specifications "ResourceType=internet-gateway,Tags=[{Key=Name,Value=$IGW_NAME}]" \
            --query 'InternetGateway.InternetGatewayId' \
            --output text)
        if [ -z "$IGW_ID" ]; then
            echo "IGW not created.\nCan not proceed further."
            exit
        fi
        echo "IGW created. ID: $IGW_ID\nAttaching it to VPC..."
        aws ec2 attach-internet-gateway \
          --internet-gateway-id $IGW_ID \
          --vpc-id $VPC_ID
        echo "IGW attached to VPC\n"

    else
        echo "IGW exists. ID: $EXISTS"
        IGW_ID=$EXISTS
    fi

    # Set the CIDR blocks for the subnets
    echo "Setting up Subnets for this VPC"
    # Create the subnets
    SUBNET_ID_1=$(aws ec2 create-subnet --region $REGION --vpc-id "$VPC_ID" --cidr-block "$SUBNET_CIDR_1" --availability-zone ap-south-1a --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=$SUBNET_NAME_1}]" --output text --query 'Subnet.SubnetId')
    SUBNET_ID_2=$(aws ec2 create-subnet --region $REGION --vpc-id "$VPC_ID" --cidr-block "$SUBNET_CIDR_2" --availability-zone ap-south-1b --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=$SUBNET_NAME_2}]" --output text --query 'Subnet.SubnetId')

    if [ -z "$SUBNET_ID_1" ]; then
        echo "Subnet not created.\nCan not proceed further."
        exit
    fi
    if [ -z "$SUBNET_ID_2" ]; then
        echo "Subnet not created.\nCan not proceed further."
        exit
    fi

    echo "2 subnets created for VPC"

    # Create the route table
    echo "Creating Route Table"
    ROUTE_TABLE_ID=$(aws ec2 create-route-table \
        --vpc-id $VPC_ID \
        --tag-specifications "ResourceType=route-table,Tags=[{Key=Name,Value=$ROUTE_TABLE_NAME}]" \
        --query 'RouteTable.RouteTableId' \
        --output text)
    if [ -z "$ROUTE_TABLE_ID" ]; then
        echo "Route Table not created.\nCan not proceed further."
        exit
    fi
    echo "Route Table created. ID: $ROUTE_TABLE_ID\n"

    # Create the public route
    echo "Creating Public Route"
    PUB_ROUTE=$(aws ec2 create-route \
        --route-table-id $ROUTE_TABLE_ID \
        --destination-cidr-block 0.0.0.0/0 \
        --gateway-id $IGW_ID)
    if [ -z "$PUB_ROUTE" ]; then
        echo "Public Route not created.\nCan not proceed further."
        exit
    fi
    echo "Public Route created\n"

    # Associate the route table with the subnet
    echo "Attaching Public Route to subnet $SUBNET_NAME_1"
    ASSOC_PUB_ROUTE=$(aws ec2 associate-route-table \
        --route-table-id $ROUTE_TABLE_ID \
        --subnet-id $SUBNET_ID_1)
    echo "Public Route attached to $SUBNET_NAME_1\n"

else
  echo "VPC with name $VPC_NAME found with ID $VPC_ID"
  # SUBNET_ID_1=$(aws ec2 describe-subnets --region $REGION --filters "Name=vpc-id,Values=$VPC_ID" --output text)
  SUBNET_ID_1=$(aws ec2 describe-subnets --region $REGION --filters "Name=vpc-id,Values=$VPC_ID" \
    --output text | sed 's/\s\+/ /g' | grep -A 2 "Name $SUBNET_NAME_1" | rev | cut -d' ' -f2 | rev | tail -2 | head -1)
  echo "Using Subnet ID: $SUBNET_ID_1"

  if [ -z "$SUBNET_ID_1" ]; then
        echo "Subnet ID not found.\nCan not proceed further."
        exit
  fi

fi

############################################################

############################################################
# Start setting Up Security Group
echo ""
echo "Creating Security Group..."
# Search for security groups with the specified name
SECURITY_GROUP_ID=$(aws ec2 describe-security-groups --filters "Name=group-name,Values=$SECURITY_GROUP_NAME" --query "SecurityGroups[*].GroupId" --output text)

# Check if a security group was found
if [ -z "$SECURITY_GROUP_ID" ]; then
    echo "Need to create new Security Group"
    # Create the security group
    SECURITY_GROUP_ID=$(aws ec2 create-security-group --region $REGION --vpc-id "$VPC_ID" --group-name $SECURITY_GROUP_NAME --description "$GROUP_DESCRIPTION" --tag-specifications "ResourceType=security-group,Tags=[{Key=Name,Value=$SECURITY_GROUP_NAME}]" --query "GroupId" --output text)
else
  echo "Security group with name $SECURITY_GROUP_NAME already exists"
fi

echo  "Security GROUP_ID" >> log.txt
echo  $SECURITY_GROUP_ID >> log.txt

echo "Security Group created. ID: $SECURITY_GROUP_ID\n"

echo "Enabling port 22"
# Allow inbound traffic on port 22 for SSH
ENABLED_PORT_22=$(aws ec2 authorize-security-group-ingress \
    --region $REGION --group-id $SECURITY_GROUP_ID \
    --protocol tcp \
    --port 22 \
    --cidr 0.0.0.0/0 \
    --tag-specifications "ResourceType=security-group-rule,Tags=[{Key=Name,Value=$PORT_22_NAME}]" \
    --output text)
echo "Port 22 enabled\n"

if [ "$OPTION" = '1' ]; then
    # Allow inbound traffic on port 80 for HTTP
    echo "Enabling port 80"
    ENABLED_PORT_80=$(aws ec2 authorize-security-group-ingress --region $REGION \
        --group-id $SECURITY_GROUP_ID \
        --protocol tcp \
        --port 80 \
        --cidr 0.0.0.0/0 \
        --tag-specifications "ResourceType=security-group-rule,Tags=[{Key=Name,Value=$PORT_22_NAME}]" \
        --output text)
    echo "Port 80 enabled\n"

    # Allow inbound traffic on port 443 for HTTPS
    echo "Enabling port 443"
    ENABLED_PORT_443=$(aws ec2 authorize-security-group-ingress \
        --region $REGION \
        --group-id $SECURITY_GROUP_ID \
        --protocol tcp \
        --port 443 \
        --cidr 0.0.0.0/0 \
        --tag-specifications "ResourceType=security-group-rule,Tags=[{Key=Name,Value=$PORT_22_NAME}]" \
        --output text)
    echo "Port 443 enabled\n"
fi

echo "Security Group setting done.\n"
# End setting Up Security Group
############################################################


# Get the image ID of the latest Ubuntu 20.04 AMI
echo "Fetching Latest Image of Ubuntu 20.04"
IMAGE_ID=$(aws ec2 describe-images --owners 099720109477 --filters "Name=name,Values=ubuntu/images/hvm-ssd/ubuntu-focal-20.04-amd64-server-*" "Name=state,Values=available" --query 'sort_by(Images, &CreationDate)[-1].ImageId' --output text --region $REGION)
echo "The image ID of the latest Ubuntu 20.04 AMI is $IMAGE_ID"

echo  "IMAGE_ID" >> log.txt
echo  $IMAGE_ID >> log.txt

if [ "$OPTION" = "1" ]; then
    USER_DATA="#!/bin/bash
        apt-get update
        apt-get install -y https://s3.amazonaws.com/ec2-downloads-windows/SSMAgent/latest/debian_amd64/amazon-ssm-agent.deb
        systemctl enable amazon-ssm-agent
        systemctl start amazon-ssm-agent
        sudo apt-get install -y software-properties-common
        sudo add-apt-repository -y ppa:ondrej/php
        sudo apt-get update
        sudo apt-get install -y apache2
        sudo apt-get install -y php7.2 php7.2-curl php7.2-json php7.2-cgi php7.2-xsl php7.2-mbstring php7.2-fpm php7.2-common php7.2-mysql libapache2-mod-php7.2 php7.2-gd php7.2-mbstring php7.2-xml
        sudo a2enmod headers rewrite
        sudo service apache2 restart
        sudo a2enmod actions fastcgi alias proxy_fcgi
        sudo service apache2 restart
        wget https://raw.githubusercontent.com/deepghorela/create-vhost-ubuntu/main/virtualhost.sh -O virtualhost.sh
        sudo chmod ugo+x virtualhost.sh
        sudo chmod ugo+rw -R /var/www/html/
        mkdir /var/www/html/$DOMAIN_DIR
        sudo chmod ugo+rw -R /var/www/html/$DOMAIN_DIR
        sudo ./virtualhost.sh create $DOMAIN_NAME /var/www/html/$DOMAIN_DIR
        sudo chmod ugo+rw -R /var/www/html/$DOMAIN_DIR
        echo '<?php 
        phpinfo();' > /var/www/html/$DOMAIN_DIR/phpinfo.php"
else
    USER_DATA="#!/bin/bash
        apt-get update"
fi

############################################################
# Launch the EC2 instance
echo ""
echo "Launching EC2 instance"
INSTANCE_ID=$(aws ec2 run-instances \
    --region $REGION \
    --image-id $IMAGE_ID  \
    --count 1 --instance-type $INSTANCE_TYPE \
    --key-name $KEY_NAME \
    --block-device-mappings "[{\"DeviceName\": \"/dev/sda1\",\"Ebs\":{\"VolumeSize\":$VOLUME_SIZE}}]" \
    --network-interfaces "DeviceIndex=0,SubnetId=$SUBNET_ID_1,Groups=$SECURITY_GROUP_ID,AssociatePublicIpAddress=true" \
    --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=$EC2_INSTANCE_NAME}]" \
    --query 'Instances[0].InstanceId' \
    --user-data "$USER_DATA" \
    --output text)


if [ -z "$INSTANCE_ID" ]; then
    echo "Some technincal issues. Can not launch instance"
    exit
fi
# Get the instance ID of the newly launched EC2 instance
#INSTANCE_ID=$(aws ec2 describe-instances --region $REGION --query 'Reservations[0].Instances[0].InstanceId' --output text)

echo  "INSTANCE_ID" >> log.txt
echo  $INSTANCE_ID >> log.txt
echo "Instance created. ID: $INSTANCE_ID"

# Wait for the instance to be running
echo "Wait for the instance to be running & Both status checks are Ok"
aws ec2 wait instance-status-ok --instance-ids "$INSTANCE_ID"

echo "Instance ready"

# Install PHP 7.2 on the EC2 instance
# echo ""
# echo "Setting up Apache and Installing PHP7.2"
# STATE=$(aws ec2 describe-instances --instance-ids $INSTANCE_ID --query 'Reservations[*].Instances[*].State.Name' --output text)

# if [ "$STATE" = "running" ]; then
#     echo "Instance $INSTANCE_ID is running"
#     RUN_COMMANDS=$(aws ssm describe-instance-information \
# 	--region $REGION \
# 	--instance-information-filter-list key=InstanceIds,valueSet=$INSTANCE_ID \
# 	--query "InstanceInformationList" \
#     --output text)

#     echo $RUN_COMMANDS

#     RUN_COMMANDS=$(aws ssm send-command \
#         --instance-ids $INSTANCE_ID \
#         --region $REGION \
#         --document-name "AWS-RunShellScript" \
#         --parameters 'commands=["sudo apt-get update", "sudo apt-get install -y software-properties-common", "sudo add-apt-repository -y ppa:ondrej/php", "sudo apt-get update", "sudo apt-get install -y apache2", "sudo apt-get install -y php7.2 php7.2-curl php7.2-json php7.2-cgi php7.2-xsl php7.2-mbstring php7.2-fpm php7.2-common php7.2-mysql libapache2-mod-php7.2 php7.2-gd php7.2-mbstring php7.2-xml", "sudo a2enmod headers rewrite", "sudo service apache2 restart"]' \
#         --output text)
#     echo "Setup done."
# else
#     echo "Instance $INSTANCE_ID is not running, can not setup apache & install PHP7.2"
# fi

echo "\nNaming Volumes attached to this instance\n"
# Get the list of volumes
volumes=$(aws ec2 describe-volumes --region $REGION --filters "Name=attachment.instance-id,Values=$INSTANCE_ID" --query "Volumes[*].VolumeId" --output text)
# Set the tag for each volume
for volume in $volumes; do
    echo "Volume ID: $volume"
    aws ec2 create-tags --resources $volume --tags Key=Name,Value=$DEFAULT_NAME"Vol"
done
echo "Naming Volumes process done"

# Allocate an Elastic IP address
echo ""
echo "Assigning Elastic IP to it"
EXISTS=$(aws ec2 describe-addresses --region $REGION --filters "Name=tag:Name,Values=$EIP_NAME" --output text --query 'Addresses[*].AllocationId')

if [ -z "$EXISTS" ]; then
    echo "Need to allocate new Elastic IP"
    ELASTIC_IP=$(aws ec2 allocate-address --region $REGION --domain vpc --tag-specifications "ResourceType=elastic-ip,Tags=[{Key=Name,Value=$EIP_NAME}]" --query 'PublicIp' --output text)
    # Associate the Elastic IP address with the EC2 instance
    ASSOCIATE_EIP=$(aws ec2 associate-address --region $REGION --instance-id $INSTANCE_ID --output text --public-ip $ELASTIC_IP)
else
    echo "EIP with tag value $EIP_NAME exists with allocation ID $EXISTS"
    ALLOCATION_ID=$EXISTS
    # Associate the Elastic IP address with the EC2 instance
    ELASTIC_IP=$(aws ec2 describe-addresses --region $REGION --allocation-id $ALLOCATION_ID --query "Addresses[*].PublicIp")
    ASSOCIATE_EIP=$(aws ec2 associate-address --region $REGION --instance-id $INSTANCE_ID --output text --public-ip $ELASTIC_IP)
fi

echo "Elastic IP $ELASTIC_IP assigned"
echo  "ELASTIC_IP" >> log.txt
echo  $ELASTIC_IP >> log.txt


if [ "$OPTION" = "1" ];then
echo "Now you can visit: http://$ELASTIC_IP"
elif [ "$OPTION" = "2" ];then
echo "Connect with your instance with:\nssh -i $KEY_NAME.pem ubuntu@$ELASTIC_IP\n"
fi
echo "All done. Thanks! :)"

# Ends Launch the EC2 instance
############################################################
# 
# --block-device-mappings "[{\"DeviceName\":\"/dev/sdf\",\"Ebs\":{},\"VolumeId\":\"$VOLUME_ID\"}]" \
# Add more volume to instance
# --block-device-mappings "[{\"DeviceName\": \"/dev/xvdf\",\"Ebs\":{\"VolumeSize\":$VOLUME_SIZE}}]" \