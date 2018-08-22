## 关闭SELinux
setenforce 0
sed -i 's/SELINUX=enforcing/SELINUX=disabled/g' /etc/selinux/config
## 设置参数
cat <<EOF | tee /etc/sysctl.d/k8s.conf
net.ipv4.ip_forward = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
EOF
sysctl -p /etc/sysctl.d/k8s.conf
## 禁用swap
swapoff -a && sysctl -w vm.swappiness=0
sed '/swap.img/d' -i /etc/fstab #不同机器可能不同
sed -i 's/(^.centos-swap swap.$)/#\1/' /etc/fstab

systemctl enabel docker && systemctl start docker

cat <<EOF > /etc/yum.repos.d/kubernetes.repo
[kubernetes]
name=Kubernetes
baseurl=https://packages.cloud.google.com/yum/repos/kubernetes-el7-x86_64
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=https://packages.cloud.google.com/yum/doc/yum-key.gpg https://packages.cloud.google.com/yum/doc/rpm-package-key.gpg
exclude=kube*
EOF
yum install -y kubelet kubeadm kubectl --disableexcludes=kubernetes
systemctl enable kubelet && systemctl start kubelet

kubeadm init --service-cidr 10.96.0.0/12 --pod-network-cidr 10.244.0.0/16 --apiserver-advertise-address 10.128.0.2

kubectl apply -f https://raw.githubusercontent.com/coreos/flannel/v0.10.0/Documentation/kube-flannel.yml

kubeadm join 10.128.0.2:6443 --token l4o5rl.y0xr3cck26jeic7k --discovery-token-ca-cert-hash sha256:03c765cda56793a0e9eb9a1c648523a58857da0a92bcdd1e3801f38edab8eb4e