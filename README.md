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

The following scripts deploy on two different regions us-west-1 and us-west-2.

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
