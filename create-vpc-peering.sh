#!/bin/bash

# Fetch VPc
vpc_west1=$(aws ec2 describe-vpcs --region us-west-1 --filter Name=tag:Name,Values=eksctl-small-us-west-1-cluster/VPC --query "Vpcs[*].VpcId" --output text)
vpc_west2=$(aws ec2 describe-vpcs --region us-west-2 --filter Name=tag:Name,Values=eksctl-small-us-west-2-cluster/VPC --query "Vpcs[*].VpcId" --output text)

# Create VPC peering connection from us-west-1

aws ec2 create-vpc-peering-connection --region us-west-1 --peer-vpc-id $vpc_west2 --vpc-id $vpc_west1 --peer-region us-west-2 --tag-specifications 'ResourceType=vpc-peering-connection,Tags=[{Key=Name,Value=2eks-vpc-peer}]'

# Get ID and Accept VPC peering connection at us-west-2

vpc_peering_id=$(aws ec2 describe-vpc-peering-connections  --region us-west-1  --filter Name=tag:Name,Values=2eks-vpc-peer --query VpcPeeringConnections[*].VpcPeeringConnectionId --output text)

aws ec2 accept-vpc-peering-connection --vpc-peering-connection-id $vpc_peering_id --region us-west-2

# Display state after 10 seconds (should be active)

sleep 10
echo "Display vpc peering state after 10 seconds..."
aws ec2 describe-vpc-peering-connections  --region us-west-1  --filter Name=tag:Name,Values=2eks-vpc-peer  --query VpcPeeringConnections[*].Status

# Update route-tables via vpc-peering

echo "Updating route-tables with routes via vpc-peering"

rtbl_west1=$(aws ec2 describe-route-tables  --region us-west-1 --filter Name=tag:Name,Values=eksctl-small-us-west-1-cluster/PublicRouteTable --query RouteTables[*].RouteTableId --output text)

rtbl_west2=$(aws ec2 describe-route-tables  --region us-west-2 --filter Name=tag:Name,Values=eksctl-small-us-west-2-cluster/PublicRouteTable --query RouteTables[*].RouteTableId --output text)
"updating 10.20/16 in us-west-1..."
aws ec2 create-route --destination-cidr-block 10.20.0.0/16 --vpc-peering-connection-id $vpc_peering_id  --route-table-id $rtbl_west1 --region us-west-1
"updating 10.10/16 in us-west-2...
aws ec2 create-route --destination-cidr-block 10.10.0.0/16 --vpc-peering-connection-id $vpc_peering_id  --route-table-id $rtbl_west2 --region us-west-2


# Update security-groups

echo "Updating security-groups with permit all"

sg_west1=$(aws ec2  describe-security-groups --region us-west-1 --filter Name=tag:Name,Values=eksctl-small-us-west-1-nodegroup-ng-west-1/SG --query SecurityGroups[*].GroupId --output text)
sg_west2=$(aws ec2  describe-security-groups --region us-west-2 --filter Name=tag:Name,Values=eksctl-small-us-west-2-nodegroup-ng-west-2/SG --query SecurityGroups[*].GroupId --output text)

echo "Updating sg for VPC us-west-1..."
aws ec2 authorize-security-group-ingress --region us-west-1    --group-id $sg_west1    --protocol -1     --cidr 0.0.0.0/0
echo "Updating sg for VPC us-west-2..."
aws ec2 authorize-security-group-ingress --region us-west-2    --group-id $sg_west2    --protocol -1     --cidr 0.0.0.0/0

