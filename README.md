# EKS PLATTER INTER CLUSTER

## Sources

Extensively derived from marcel's work
https://ssd-git.juniper.net/rpd/platter/-/blob/eks/eks/

## Prerequisites

- Install aws cli
- Install eksctl
- Install jq
- Docker installation

## Short story

Deployment of platter on two different EKS clusters running in two regions us-west-1 and us-west-2. 
AWS VPC peering is enforced to connect the underlying VPCs on which EKS clusters are deployed. 
This all starts with two ekstctl command to create clusters.

![image](https://user-images.githubusercontent.com/21667569/125673627-3a7e27a5-ee69-44f0-a8b2-1d60bd33e361.png)

Next platter is deployed on both clusters.
So far:
- manual peering is required to connect both clusters via MP-BGP at RR level
- only VXLAN is supported 
- kernel forwarding (issues requiring rpd restart)

![image](https://user-images.githubusercontent.com/21667569/125674512-7cfaec61-6e57-4a7c-afa9-ca272a3c94b1.png)

Here is an example of the manual inter-cluster peering (push appropriate IPs instead) that requires automation (next stages).

```
##### RR us-west-1 (VPC has 10.10/16 CIDR)

group inter-cluster {
    type internal;
    local-address 10.10.58.82;
    family inet-vpn {
        unicast;
    }
    family inet6-vpn {
        unicast;
    }
    family evpn {
        signaling;
    }
    local-as 64512;
    neighbor 10.20.20.100;
}

##### RR us-west-2 (VPC has 10.20/16 CIDR)

group inter-cluster {
    type internal;
    local-address 10.20.20.100;
    family inet-vpn {
        unicast;
    }
    family inet6-vpn {
        unicast;
    }
    family evpn {
        signaling;
    }
    local-as 64512;
    neighbor 10.10.58.82;
}
```


# Step by Step

## Initialise ECR repositories with platter and cRPD images 

*Create ECR in each DCs*

- Create ECR repositories for platter and crpd in each regions
- Connect docker 
- Push crpd and platter in ECRs

```
AWS_REGIONS=('us-west-1' 'us-west-2')
for region in "${AWS_REGIONS[@]}"
do
 aws ecr create-repository \
    --repository-name crpd \
    --image-scanning-configuration scanOnPush=false \
    --region $region
 aws ecr create-repository \
    --repository-name platter \
    --image-scanning-configuration scanOnPush=false \
    --region $region
 aws_repos=$(aws ecr describe-repositories --region $region)
 ecr_id=$(echo $aws_repos | jq '.repositories[].repositoryUri | select (. | contains ("crpd"))?' | sed 's/\/crpd//' | sed 's/"//g')

 aws ecr get-login-password --region $region | sudo docker login --username AWS \
  --password-stdin $ecr_id
 
 sudo docker tag crpd:21.3I20210427_1631 $ecr_id/crpd:21.3I20210427_1631
 sudo docker tag platter:latest $ecr_id/platter:latest
 sudo docker push $ecr_id/crpd:21.3I20210427_1631
 sudo docker push $ecr_id/platter:latest

done
```

Run eksctl to create the cluster
```
eksctl create cluster -f  small-eks-us-west-1.yaml
eksctl create cluster -f  small-eks-us-west-2.yaml
```
Run deploy-platter.sh (should have all the logic to deploy platter over the two clusters created above). This script is a wrapper that calls several other scripts.

```
sh ./deploy-platter.sh 
```
Deploy pods
```
sh ./deploy-overlay-demo.sh 
```



