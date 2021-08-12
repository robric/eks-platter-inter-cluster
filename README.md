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

Deployment of platter on two different EKS clusters running in two regions us-west-1 and us-west-2. 
AWS VPC peering is enforced to connect the underlying VPCs on which EKS clusters are deployed. 
This all starts with two ekstctl command to create clusters.

![image](https://user-images.githubusercontent.com/21667569/125673627-3a7e27a5-ee69-44f0-a8b2-1d60bd33e361.png)

Next platter is deployed on both clusters.
So far:
- manual peering is required to connect both clusters via MP-BGP at RR level
- only VXLAN is supported 
- kernel forwarding (issues requiring rpd restart)

![image](https://user-images.githubusercontent.com/21667569/125674512-7cfaec61-6e57-4a7c-afa9-ca272a3c94b1.png)

Here is an example of the manual inter-cluster peering (push appropriate IPs instead) that requires automation (next stages).

```
##### RR us-west-1 (VPC has 10.10/16 CIDR)

group inter-cluster {
    type internal;
    local-address 10.10.58.82;
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
    neighbor 10.20.20.100;
}

##### RR us-west-2 (VPC has 10.20/16 CIDR)

group inter-cluster {
    type internal;
    local-address 10.20.20.100;
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
    neighbor 10.10.58.82;
}
```


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

To interconnect the VPC clusters, execute the following script.

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
Or more concretely follow this example
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

## POD deployment

Launch a single pod in each cluster/region. The manifests will the following pods with IP in VRF blue-net
* 1.1.1.2/32 for pod alpine-cluster-1 in us-west-1 
* 1.2.2.2/32 for pod alpine-cluster-2 in us-west-2

```
 kubectl config use-context dsundarraj@small-us-west-1.us-west-1.eksctl.io
 kubectl apply -f alpine-cluster-1.yaml
 kubectl config use-context dsundarraj@small-us-west-2.us-west-2.eksctl.io
 kubectl apply -f alpine-cluster-2.yaml
```
Check the status of the pod and launch 
```



