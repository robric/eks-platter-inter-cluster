#!/bin/bash

echo "platter-config.yaml ..."
masterip=$(kubectl get nodes -A -o json |jq -r .items[].status.addresses[].address|grep -v compute|grep 10.20|head -1)
echo "setting bgp neighbor to master $masterip ..."
sed -i "s/neighbor .*/neighbor $masterip;/" platter-config.yaml

echo "platter-node-config.yaml ..."
cat <<EOF >platter-node-config.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: platter-node-config
  namespace: kube-system
data:
EOF
nodes=$(kubectl get nodes -A -o json| jq -r .items[].metadata.name)
i=0
for node in $nodes; do
  echo -n $node ...
  ip=$(kubectl get nodes $node -o json |jq -r .status.addresses[].address|grep -v compute|grep 10.20)
  echo "ip=$ip"
  cat <<EOF >>platter-node-config.yaml
  node-$node.json: |
    {
      "ipv4LoopbackAddr":"$ip",
      "ipv6LoopbackAddr":"abcd::$ip",
      "isoLoopbackAddr":"49.0004.1000.0000.000$i.00",
      "srIPv4NodeIndex":"200$i",
      "srIPv6NodeIndex":"300$i"
    }
EOF
  i=$(expr $i + 1)
done
