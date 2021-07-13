#!/bin/bash

kubectl config use-context   dsundarraj@small-us-west-1.us-west-1.eksctl.io
kubectl apply -f platter-nad-blue-evpn.yaml
kubectl apply -f alpine-cluster-1.yaml

kubectl config use-context   dsundarraj@small-us-west-2.us-west-2.eksctl.io
kubectl apply -f platter-nad-blue-evpn.yaml
kubectl apply -f alpine-cluster-2.yaml

