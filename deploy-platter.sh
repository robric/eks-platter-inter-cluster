#!/bin/bash

set -e

#fixing SNAT + source-dest-check
./fix-source-dest-check-and-snat.sh 

echo "load kernel modules on all nodes ..."
./load-node-modules.sh

echo "load kubelet.conf on all nodes ..."
./load-kubelet-conf.sh

echo "Build specific platter-cluster-X.yaml files with ecr for each region"
./fix-platter.sh


kubectl config use-context   dsundarraj@small-us-west-1.us-west-1.eksctl.io

echo "fixing platter-config.yaml and platter-node-config.yaml ..."
./fixing-configs-cluster-1.sh 

echo "label one node as master ..."
./label-master-node.sh

echo "installing platter ..."
kubectl apply -f platter-secrets.yaml
kubectl apply -f platter-config.yaml
kubectl apply -f platter-node-config.yaml
kubectl apply -f platter-cluster-1.yaml
kubectl apply -f multus-daemonset.yml
kubectl apply -f platter-nad-blue-evpn.yaml

kubectl config use-context   dsundarraj@small-us-west-2.us-west-2.eksctl.io



echo "fixing platter-config.yaml and platter-node-config.yaml ..."
./fixing-configs-cluster-2.sh

echo "label one node as master ..."
./label-master-node.sh

echo "installing platter ..."
kubectl apply -f platter-secrets.yaml
kubectl apply -f platter-config.yaml
kubectl apply -f platter-node-config.yaml
kubectl apply -f platter-cluster-2.yaml
kubectl apply -f multus-daemonset.yml
kubectl apply -f platter-nad-blue-evpn.yaml



