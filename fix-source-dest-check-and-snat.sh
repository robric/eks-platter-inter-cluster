
echo "fixing SNAT for 1.1/16 in us-west-1..."

kubectl config use-context   dsundarraj@small-us-west-1.us-west-1.eksctl.io
kubectl set env daemonset -n kube-system aws-node AWS_VPC_K8S_CNI_EXCLUDE_SNAT_CIDRS=1.1.0.0/16

echo "fixing SNAT for 1.2/16 in us-west-2..."

kubectl config use-context   dsundarraj@small-us-west-2.us-west-2.eksctl.io
kubectl set env daemonset -n kube-system aws-node AWS_VPC_K8S_CNI_EXCLUDE_SNAT_CIDRS=1.2.0.0/16

echo "Disabling source-dest-check on us-west-1..."

aws ec2 describe-instances --filter Name=tag:eksctl.cluster.k8s.io/v1alpha1/cluster-name,Values=small-us-west-1 --region us-west-1 --query "Reservations[*].Instances[*].NetworkInterfaces[*].[NetworkInterfaceId]" --output text | xargs -I {} aws ec2 modify-network-interface-attribute --region us-west-1 --network-interface-id {} --no-source-dest-check

echo "Disabling source-dest-check on us-west-2..."

aws ec2 describe-instances --filter Name=tag:eksctl.cluster.k8s.io/v1alpha1/cluster-name,Values=small-us-west-2 --region us-west-2 --query "Reservations[*].Instances[*].NetworkInterfaces[*].[NetworkInterfaceId]" --output text | xargs -I {} aws ec2 modify-network-interface-attribute --region us-west-2 --network-interface-id {} --no-source-dest-check

