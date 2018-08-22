  for NODE in k8s-n1; do
    ssh ${NODE} "systemctl stop docker && systemctl stop kubelet && systemctl disable kubelet.service"
    ssh ${NODE} "umount $(df -HT | grep '/var/lib/kubelet/pods' | awk '{print $7}') && rm -rf /var/lib/kubelet"
    ssh ${NODE} "rm -rf /etc/kubernetes && rm -rf ~/.kube && rm -rf /etc/etcd && rm -rf /var/log/kubernetes && rm -rf /var/lib/etcd && rm -rf /etc/systemd/system/kubelet.service.d && rm -rf /usr/local/bin/kubelet && rm -rf /usr/local/bin/kubectl"
    echo ""
    echo "== stop & disable firewalld, set SELINUX disabled @${NODE} =="
    ssh ${NODE} "systemctl stop firewalld && systemctl disable firewalld && setenforce 0 && sed -i 's/SELINUX=enforcing/SELINUX=disabled/g' /etc/selinux/config"

    echo ""
    echo "== install docker latest @${NODE} =="
    #curl -fsSL https://get.docker.com/ | sh
    ssh ${NODE} "systemctl enable docker && systemctl start docker"

    echo ""
    echo "== set k8s config param @${NODE} =="
    ssh ${NODE} "cat <<EOF | tee /etc/sysctl.d/k8s.conf
net.ipv4.ip_forward = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
EOF"
    ssh ${NODE} "sysctl -p /etc/sysctl.d/k8s.conf"

    echo ""
    echo "== close swap @${NODE} =="
    ssh ${NODE} "swapoff -a && sysctl -w vm.swappiness=0"
    ssh ${NODE} "sed '/swap.img/d' -i /etc/fstab"
    ssh ${NODE} "sed -i 's/\(^.*centos-swap swap.*$\)/#\1/' /etc/fstab"

    echo ""
    echo "== install kubelet & kubectl @${NODE} =="
    #wget ${KUBE_URL}/kubelet -O /usr/local/bin/kubelet --no-cookie --no-check-certificate
    #wget ${KUBE_URL}/kubectl -O /usr/local/bin/kubectl
    #chmod +x /usr/local/bin/kubectl
    ssh ${NODE} "if [ ! -x '/usr/local/bin/kubelet' ]; then
      curl -o /usr/local/bin/kubelet https://storage.googleapis.com/kubernetes-release/release/v1.11.0/bin/linux/amd64/kubelet -k
      chmod +x /usr/local/bin/kubelet
    fi
    if [ ! -x '/usr/local/bin/kubectl' ]; then
      curl -o /usr/local/bin/kubectl https://storage.googleapis.com/kubernetes-release/release/v1.11.0/bin/linux/amd64/kubectl -k
      chmod +x /usr/local/bin/kubectl
    fi"

    echo ""
    echo "== download CNI @${NODE} =="
    ssh ${NODE} "mkdir -p /opt/cni/bin && cd /opt/cni/bin"
    #wget -qO- --show-progress "${CNI_URL}/v0.7.1/cni-plugins-amd64-v0.7.1.tgz" | tar -zx
    ssh ${NODE} "if [ ! '$(ls -A /opt/cni/bin)' ]; then
      wget 'https://github.com/containernetworking/plugins/releases/download/v0.7.1/cni-plugins-amd64-v0.7.1.tgz'
      tar zxfv cni-plugins-amd64-v0.7.1.tgz -C /opt/cni/bin/
    fi"

    ssh ${NODE} "mkdir -p /etc/kubernetes/pki/"
    for FILE in pki/ca.pem pki/ca-key.pem bootstrap-kubelet.conf; do
      scp /etc/kubernetes/${FILE} ${NODE}:/etc/kubernetes/${FILE}
    done

    cd ~/k8s-manual-files

    ssh ${NODE} "mkdir -p /var/lib/kubelet /var/log/kubernetes /var/lib/etcd /etc/systemd/system/kubelet.service.d /etc/kubernetes/manifests"
    scp node/var/lib/kubelet/config.yml ${NODE}:/var/lib/kubelet/config.yml
    scp node/systemd/kubelet.service ${NODE}:/lib/systemd/system/kubelet.service
    scp node/systemd/10-kubelet.conf ${NODE}:/etc/systemd/system/kubelet.service.d/10-kubelet.conf

    ssh ${NODE} "systemctl daemon-reload && systemctl start kubelet.service && systemctl enable kubelet.service"

done

  