#/bin/bash
node1=$(kubectl get nodes -A -o json |jq -r .items[].metadata.name|head -1)
echo "label $node1 with master role ..."
kubectl label node $node1 node-role.kubernetes.io/master=master
