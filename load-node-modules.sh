#/bin/bash
nodes=$(aws ec2 describe-instances --filter Name=tag:eksctl.cluster.k8s.io/v1alpha1/cluster-name,Values=small-us-west-1 --region us-west-1 --query "Reservations[*].Instances[*].NetworkInterfaces[*].PrivateIpAddresses[*].Association.PublicIp" --output text)" "$(aws ec2 describe-instances --filter Name=tag:eksctl.cluster.k8s.io/v1alpha1/cluster-name,Values=small-us-west-2 --region us-west-2 --query "Reservations[*].Instances[*].NetworkInterfaces[*].PrivateIpAddresses[*].Association.PublicIp" --output text)

i=0
for node in $nodes; do
  echo "$node ..."
  let i=i+1
  ssh -o StrictHostKeyChecking=no ec2-user@$node uname -a
  for module in ip_tunnel mpls_gso vxlan; do
    echo -n "$module ... "
    ssh ec2-user@$node sudo modprobe $module
  done
done
