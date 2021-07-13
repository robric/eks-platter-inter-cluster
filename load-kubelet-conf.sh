#/bin/bash



nodes_west1=$(aws ec2 describe-instances --filter Name=tag:eksctl.cluster.k8s.io/v1alpha1/cluster-name,Values=small-us-west-1 --region us-west-1 --query "Reservations[*].Instances[*].NetworkInterfaces[*].PrivateIpAddresses[*].Association.PublicIp" --output text)
nodes_west2=$(aws ec2 describe-instances --filter Name=tag:eksctl.cluster.k8s.io/v1alpha1/cluster-name,Values=small-us-west-2 --region us-west-2 --query "Reservations[*].Instances[*].NetworkInterfaces[*].PrivateIpAddresses[*].Association.PublicIp" --output text)


kubectl config use-context   dsundarraj@small-us-west-1.us-west-1.eksctl.io

for node in $nodes_west1; do
  echo "$node ..."
  scp ~/.kube/config ec2-user@$node:
  ssh ec2-user@$node sudo mv config /etc/kubernetes/kubelet.conf
done

kubectl config use-context   dsundarraj@small-us-west-2.us-west-2.eksctl.io

for node in $nodes_west2; do
	  echo "$node ..."
	    scp ~/.kube/config ec2-user@$node:
	      ssh ec2-user@$node sudo mv config /etc/kubernetes/kubelet.conf
done
