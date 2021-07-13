#!/bin/bash
#
echo "Pushing aws ecr locations to platter.yaml in us-west-1 ..."

crpd_repo=$(aws ecr   describe-repositories  --region us-west-1  --repository-names crpd --query repositories[*].repositoryUri --output text)

platter_repo=$(aws ecr   describe-repositories  --region us-west-1  --repository-names platter --query repositories[*].repositoryUri --output text)

crpd_uri=$crpd_repo:$(aws ecr   describe-images --region us-west-1  --repository-name crpd --query imageDetails[*].imageTags --output text)

platter_uri=$platter_repo:$(aws ecr describe-images --region us-west-1  --repository-name platter --query imageDetails[*].imageTags --output text)

sed "s|platter-image.*|$platter_uri|g"  platter.yaml | sed "s|crpd-image.*|$crpd_uri|g"  > platter-cluster-1.yaml

#sed -i "s|platter-image.*|$platter_uri|g"  platter.yaml 
#sed -i "s|crpd-image.*|$crpd_uri|g"  platter.yaml 

echo "Pushing aws ecr locations to platter.yaml in us-west-2 ..."

crpd_repo=$(aws ecr   describe-repositories  --region us-west-2  --repository-names crpd --query repositories[*].repositoryUri --output text)

platter_repo=$(aws ecr   describe-repositories  --region us-west-2  --repository-names platter --query repositories[*].repositoryUri --output text)

crpd_uri=$crpd_repo:$(aws ecr   describe-images --region us-west-2  --repository-name crpd --query imageDetails[*].imageTags --output text)

platter_uri=$platter_repo:$(aws ecr describe-images --region us-west-2  --repository-name platter --query imageDetails[*].imageTags --output text)


sed "s|platter-image.*|$platter_uri|g"  platter.yaml | sed "s|crpd-image.*|$crpd_uri|g"  > platter-cluster-2.yaml
