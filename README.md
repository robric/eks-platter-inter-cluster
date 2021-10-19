# EKS PLATTER INTER CLUSTER

## Sources

Marcel's work on platter deployment over EKS
https://ssd-git.juniper.net/rpd/platter/-/blob/eks/eks/

## Prerequisites

On a deployer node, install the following tooling:
- Install aws cli
- Install eksctl
- Install jq
- Docker installation

## Short story

The objective is to deploy the platter CNI (cRPD based) on two different EKS clusters running in two distinct AWS regions us-west-1 and us-west-2. 

The aws "VPC peering" logic is enforced to connect the underlying VPCs on which the EKS clusters are deployed. This permits to non-NAT L3-connectivity between the EKS clusters.

![image](https://user-images.githubusercontent.com/21667569/125673627-3a7e27a5-ee69-44f0-a8b2-1d60bd33e361.png)

Platter is deployed on each cluster, with a master (i.e. route-reflector)/worker pattern. An inter-cluster MP-BGP peering is established between master to synchronize the overlay routing between clusters.

![image](https://user-images.githubusercontent.com/21667569/125674512-7cfaec61-6e57-4a7c-afa9-ca272a3c94b1.png)

After this infrastructure is deployed, it is possible to launch pods in each cluster and provide secured and seamless connectivity connectivity between pods over VXLAN. From a forwarding standpoint, the VPCs are the underlay supporting the VXLAN overlay in which pod traffic is propagated.

![image](https://user-images.githubusercontent.com/21667569/129240370-bbe97810-ce39-490f-afa4-9942ce8a2c4c.png)

This permits to connect cNFs in VRFs for isolation (green VRF vs red VRF). The attachment of the pods to the VRF is done via kubernetees thanks to the "network attachment definition" Custom ressource.

![image](https://user-images.githubusercontent.com/21667569/129240654-c32203bb-762d-4e3b-b814-06805a81b76c.png)

Footnotes
- Manual BGP peering is required to connect both clusters via MP-BGP at RR level
- Only VXLAN is supported for this proof of concept. MPLSoUDP or SRv6 are good candidate for future alternative overlays.
- The forwarding is based on native kernel linux

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

[UPDATE - and more efficient use of API filters -]

update crpd image
```console
sudo docker image load -i crpd-21.4I-20210918.docker.gz
ecr_id=$(aws ecr describe-repositories --region us-west-1 --query "repositories[?repositoryName=='crpd'].repositoryUri" --output text)
ubuntu@master:~$ sudo docker tag crpd:latest $ecr_id:latest
ubuntu@master:~$ sudo docker image list
REPOSITORY                                             TAG                  IMAGE ID       CREATED        SIZE
855275951286.dkr.ecr.us-west-1.amazonaws.com/crpd      latest               062dbe3a8fdf   12 days ago    345MB

### refresh credentials (remove .docker/config.json in root)

ubuntu@master:~$ aws ecr get-login-password --region us-west-1 | docker login --username AWS --password-stdin ########AWS_ID######.dkr.ecr.us-west-1.amazonaws.com

### Edit platter-config.yaml and replace crpd tag with latest
```

## Create two EKS clusters in two different regions

Run eksctl to create the cluster
```
eksctl create cluster -f  small-eks-us-west-1.yaml
eksctl create cluster -f  small-eks-us-west-2.yaml
```

## Deploy the platter CNI

Run the "deploy-platter.sh" script. It has all the logic to deploy platter over the two clusters created above. This script is actually a wrapper that calls several scripts.

```
sh ./deploy-platter.sh 
```
After this step all pods including cRPD should be deployed and running  should be deployed in each cluster. 
We can notice a cRPD master pod (i.e. acting as route reflector) together with two cRPD workers. Note that due to the presescriptive nature of the EKS infrastructure, the cRPD master pod is actually running on a Kubernetees worker node.
```
Example in one cluster:
ubuntu@master:~/eks-platter-inter-cluster$ kubectl get pods -A
NAMESPACE     NAME                        READY   STATUS    RESTARTS   AGE
kube-system   aws-node-9j4nj              1/1     Running   0          14h
kube-system   aws-node-gc8wm              1/1     Running   0          14h
kube-system   aws-node-jdbcr              1/1     Running   0          14h
kube-system   coredns-6548845887-2kjnt    1/1     Running   0          15h
kube-system   coredns-6548845887-t6wd6    1/1     Running   0          15h
kube-system   kube-crpd-master-ds-vzbjk   1/1     Running   0          14h
kube-system   kube-crpd-worker-ds-hpdx8   1/1     Running   0          14h
kube-system   kube-crpd-worker-ds-nw4zb   1/1     Running   0          14h
kube-system   kube-multus-ds-qjl2r        1/1     Running   0          14h
kube-system   kube-multus-ds-r7kkg        1/1     Running   0          14h
kube-system   kube-multus-ds-sr2j2        1/1     Running   0          14h
kube-system   kube-proxy-2nmcl            1/1     Running   0          15h
kube-system   kube-proxy-b9wz8            1/1     Running   0          15h
kube-system   kube-proxy-khtdx            1/1     Running   0          15h
ubuntu@master:~/eks-platter-inter-cluster$
```
You may connect to a cRPD pod to verify the completeness of the deployment. BGP peering should be established between the cRPD workers and the cRPD master.
```
ubuntu@master:~/eks-platter-inter-cluster$ kubectl get pods -o wide -n kube-system | grep crpd
kube-crpd-master-ds-vzbjk   1/1     Running   0          14h   10.20.63.45    ip-10-20-63-45.us-west-2.compute.internal   <none>           <none>
kube-crpd-worker-ds-hpdx8   1/1     Running   0          14h   10.20.9.206    ip-10-20-9-206.us-west-2.compute.internal   <none>           <none>
kube-crpd-worker-ds-nw4zb   1/1     Running   0          14h   10.20.68.97    ip-10-20-68-97.us-west-2.compute.internal   <none>           <none>

ubuntu@master:~/eks-platter-inter-cluster$ kubectl exec -it kube-crpd-master-ds-vzbjk -n kube-system -- cli
Defaulted container "kube-crpd-master" out of: kube-crpd-master, install-cni (init)
root@ip-10-20-63-45.us-west-2.compute.internal> show bgp summary 
Threading mode: BGP I/O
Default eBGP mode: advertise - accept, receive - accept
Groups: 1 Peers: 2 Down peers: 0
Unconfigured peers: 2
Table          Tot Paths  Act Paths Suppressed    History Damp State    Pending
bgp.l3vpn.0          
                       0          0          0          0          0          0
bgp.l3vpn-inet6.0    
                       0          0          0          0          0          0
bgp.evpn.0           
                       0          0          0          0          0          0
Peer                     AS      InPkt     OutPkt    OutQ   Flaps Last Up/Dwn State|#Active/Received/Accepted/Damped...
10.20.9.206           64512       2010       2000       0       0    15:00:52 Establ
  bgp.l3vpn.0: 0/0/0/0
  bgp.l3vpn-inet6.0: 0/0/0/0
  bgp.evpn.0: 0/0/0/0
10.20.68.97           64512       2010       2000       0       0    15:00:52 Establ
  bgp.l3vpn.0: 0/0/0/0
  bgp.l3vpn-inet6.0: 0/0/0/0
  bgp.evpn.0: 0/0/0/0
```
## Interconnect the EKS clusters

To interconnect the VPC clusters, execute the following script. It is made up on a sequence of aws API calls that will configure the following items
- VPC peering (request and accept)
- update route-table for inter-VPC routing
- update security-group for more permissiveness

```
sh ./create-vpc-peering.sh 
```

You can validate that VPC interconnection by pinging from a crpd instance of a region/cluster to another crpd instance in the peer cluster.
You may get pod private IPs thanks to "kubectl get pods -o wide" and switch context thanks to the "kubectl config use-context" command as per the below trace.  

```
#### Get the cRPD pod IPs - we can notice we're in the us-west-2 context thanks to the IP range (10.20).  

ubuntu@master:~/eks-platter-inter-cluster$ kubectl get pods -A -o wide | grep crpd
kube-system   kube-crpd-master-ds-vzbjk   1/1     Running   0          17h   10.20.63.45    ip-10-20-63-45.us-west-2.compute.internal   <none>           <none>
kube-system   kube-crpd-worker-ds-hpdx8   1/1     Running   0          17h   10.20.9.206    ip-10-20-9-206.us-west-2.compute.internal   <none>           <none>
kube-system   kube-crpd-worker-ds-nw4zb   1/1     Running   0          17h   10.20.68.97    ip-10-20-68-97.us-west-2.compute.internal   <none>           <none>


#### Switch  kubectl context and ping from a worker in us-west-1 to a worker in us-west-2

ubuntu@master:~/eks-platter-inter-cluster$ kubectl config use-context dsundarraj@small-us-west-1.us-west-1.eksctl.io
Switched to context "dsundarraj@small-us-west-1.us-west-1.eksctl.io".
ubuntu@master:~/eks-platter-inter-cluster$ kubectl get pods -A -o wide | grep crpd
kube-system   kube-crpd-master-ds-2v7s9   1/1     Running   0          17h   10.10.25.42    ip-10-10-25-42.us-west-1.compute.internal    <none>           <none>
kube-system   kube-crpd-worker-ds-bkl6q   1/1     Running   0          17h   10.10.93.12    ip-10-10-93-12.us-west-1.compute.internal    <none>           <none>
kube-system   kube-crpd-worker-ds-fmf9b   1/1     Running   0          17h   10.10.29.243   ip-10-10-29-243.us-west-1.compute.internal   <none>           <none>
ubuntu@master:~/eks-platter-inter-cluster$ kubectl exec -it kube-crpd-worker-ds-bkl6q -n kube-system -- ping  10.20.9.206 
Defaulted container "kube-crpd-worker" out of: kube-crpd-worker, install-cni (init)
PING 10.20.9.206 (10.20.9.206) 56(84) bytes of data.
64 bytes from 10.20.9.206: icmp_seq=1 ttl=255 time=20.9 ms
64 bytes from 10.20.9.206: icmp_seq=2 ttl=255 time=20.9 ms
64 bytes from 10.20.9.206: icmp_seq=3 ttl=255 time=20.8 ms
```
## Create inter-cluster BGP peering (manual step)

So far, the inter-cluster BGP peering must be define manually.
For this purpose,
* Capture the crpd master IP addresses (see the previous step with the ping test so get the IP) and add the matching configuration on each node.
* Load the appropriate configuration in JUNOS \[edit protocols bgp] on each master node based on the following template

```
group inter-cluster {
    type internal;
    local-address LocalcrpdMasterPodIPAddress;
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
    neighbor RemotecrpdMasterPodIPAddress;
}
```
Or, if you want it more follow this example
```

ubuntu@master:~/eks-platter-inter-cluster$ kubectl get pods -o wide -n kube-system | grep master 
kube-crpd-master-ds-2v7s9   1/1     Running   0          17h   10.10.25.42    ip-10-10-25-42.us-west-1.compute.internal    <none>           <none>
ubuntu@master:~/eks-platter-inter-cluster$ kubectl exec -it kube-crpd-master-ds-2v7s9  -n kube-system -- cli
Defaulted container "kube-crpd-master" out of: kube-crpd-master, install-cni (init)
root@ip-10-10-25-42.us-west-1.compute.internal> configure 
Entering configuration mode

[edit]
root@ip-10-10-25-42.us-west-1.compute.internal# edit protocols bgp 

[edit protocols bgp]
root@ip-10-10-25-42.us-west-1.compute.internal# load merge terminal relative 
[Type ^D at a new line to end input]
group inter-cluster {
    type internal;
    local-address 10.10.25.42;
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
    neighbor 10.20.63.45;
}
load complete

[edit protocols bgp]
root@ip-10-10-25-42.us-west-1.compute.internal# commit 
commit complete

[edit protocols bgp]
root@ip-10-10-25-42.us-west-1.compute.internal# exit 
[...]
ubuntu@master:~/eks-platter-inter-cluster$  kubectl config use-context   dsundarraj@small-us-west-2.us-west-2.eksctl.io
Switched to context "dsundarraj@small-us-west-2.us-west-2.eksctl.io".
ubuntu@master:~/eks-platter-inter-cluster$ kubectl get pods -o wide -n kube-system | grep master 
kube-crpd-master-ds-vzbjk   1/1     Running   0          17h   10.20.63.45    ip-10-20-63-45.us-west-2.compute.internal   <none>           <none>
ubuntu@master:~/eks-platter-inter-cluster$ kubectl exec -it kube-crpd-master-ds-vzbjk -n kube-system -- cli
Defaulted container "kube-crpd-master" out of: kube-crpd-master, install-cni (init)
root@ip-10-20-63-45.us-west-2.compute.internal> configure 
Entering configuration mode

[edit]
root@ip-10-20-63-45.us-west-2.compute.internal# edit protocols bgp 

[edit protocols bgp]
root@ip-10-20-63-45.us-west-2.compute.internal# load merge terminal relative 
[Type ^D at a new line to end input]
group inter-cluster {
    type internal;
    local-address 10.20.63.45;
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
    neighbor 10.10.25.42;
}
load complete

[edit protocols bgp]
root@ip-10-20-63-45.us-west-2.compute.internal# commit 
commit complete

[edit protocols bgp]
```
Verification - make sure the inter-cluster BGP peer is in the "Established" state
```
root@ip-10-20-63-45.us-west-2.compute.internal# run show bgp summary    
Threading mode: BGP I/O
Default eBGP mode: advertise - accept, receive - accept
Groups: 2 Peers: 3 Down peers: 0
Unconfigured peers: 2
Table          Tot Paths  Act Paths Suppressed    History Damp State    Pending
bgp.l3vpn.0          
                       0          0          0          0          0          0
bgp.l3vpn-inet6.0    
                       0          0          0          0          0          0
bgp.evpn.0           
                       0          0          0          0          0          0
Peer                     AS      InPkt     OutPkt    OutQ   Flaps Last Up/Dwn State|#Active/Received/Accepted/Damped...
10.10.25.42           64512          5          4       0       0           6 Establ
  bgp.l3vpn.0: 0/0/0/0
  bgp.l3vpn-inet6.0: 0/0/0/0
  bgp.evpn.0: 0/0/0/0
```
Now you're good to start playing with advanced pod networking !

## Overlay and POD deployment

The following diagram represents the deployment: it is made up of a single VRF (bound to a kubernetees network attachment definition) and a single pod in each cluster (alpine Linux).

![image](https://user-images.githubusercontent.com/21667569/129390119-6d9fb425-188d-4670-b0ba-65dc799aee08.png)
 
 The below manifests will bring-up the following logic:
* platter-nad-blue-evpn.yaml: defines of the blue-net VRF as a kubernetees "network-attachment-definition" ressource.
* alpine-cluster-1.yaml: Alpine Linux container running in pod alpine-cluster-1 with IP 1.1.1.2/32 in blue-net VRF for us-west-1 
* alpine-cluster-2.yaml: Alpine Linux container running in pod alpine-cluster-2 with IP 1.2.2.2/32 in blue-net VRF for us-west-2

The "deploy-overlay-demo.sh" script automates the manifest application.
```
ubuntu@master:~/eks-platter-inter-cluster$ sh ./deploy-overlay-demo.sh 
ubuntu@master:~/eks-platter-inter-cluster$ cat deploy-overlay-demo.sh 
#!/bin/bash

kubectl config use-context   dsundarraj@small-us-west-1.us-west-1.eksctl.io
kubectl apply -f platter-nad-blue-evpn.yaml
kubectl apply -f alpine-cluster-1.yaml

kubectl config use-context   dsundarraj@small-us-west-2.us-west-2.eksctl.io
kubectl apply -f platter-nad-blue-evpn.yaml
kubectl apply -f alpine-cluster-2.yaml
```
For quick access, the content of these manifests is provided here.
Definition of the NetworkAttachmentDefinition for the blue-net VRF with the appropriate route-target and VNI.

```
ubuntu@master:~/eks-platter-inter-cluster$ cat platter-nad-blue-evpn.yaml
apiVersion: "k8s.cni.cncf.io/v1"
kind: NetworkAttachmentDefinition
metadata:
  name: blue-net
spec:
  config: '{
    "cniVersion":"0.4.0",
    "name": "blue-net",
    "type": "platter",
    "args": {
      "applyGroups":"evpn-type5",
      "vxlanVNI":"10002",
      "vrfName": "blue",
      "vrfTarget": "11:11"
    },
    "kubeConfig":"/etc/kubernetes/kubelet.conf"
  }'
ubuntu@master:~/eks-platter-inter-cluster$ kubectl get net-attach-def
NAME       AGE
blue-net   43h
```
Example of pod with reference to the blue-net network attachment definition. Note that pod are created with remote routes as well to inter-cluster routing via the platter CNI logic.
```
ubuntu@master:~/eks-platter-inter-cluster$ cat alpine-cluster-1.yaml 
apiVersion: v1
kind: Pod
metadata:
  name:   alpine-cluster-1
  annotations:
    k8s.v1.cni.cncf.io/networks: |
      [
        {
          "name": "blue-net",
          "interface":"net1",
          "cni-args": {
            "mac":"aa:bb:cc:dd:01:01",
            "dataplane":"linux",
            "ipConfig":{
              "ipv4":{
                "address":"1.1.1.2/30",
                "gateway":"1.1.1.1",
                "routes":[
                  "1.1.0.0/16","1.2.0.0/16"
                ]
              },
              "ipv6":{
                "address":"abcd::1.1.1.2/126",
                "gateway":"abcd::1.1.1.1",
                "routes":[
                  "abcd::1.1.0.0/112"
                ]
              }
            }
          }
        }
      ]
spec:
  affinity:
    nodeAffinity:
      requiredDuringSchedulingIgnoredDuringExecution:
        nodeSelectorTerms:
          - matchExpressions:
            - key: node-role.kubernetes.io/master
              operator: NotIn
              values:
                - master
  containers:
    - name: alpine-cluster-1
[...]

```

Check the status of the pod and launch 
```



