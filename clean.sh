  for NODE in k8s-m1 k8s-m2 k8s-m3 k8s-n1; do
    ssh ${NODE} "systemctl stop docker && systemctl stop kubelet"
    ssh ${NODE} "rm -rf /etc/kubernetes && rm -rf ~/.kube && rm -rf /etc/etcd && rm -rf /var/lib/kubelet && rm -rf /var/log/kubernetes && rm -rf /var/lib/etcd && rm -rf /etc/systemd/system/kubelet.service.d && rm -rf /usr/local/bin/kubelet && rm -rf /usr/local/bin/kubectl"
done

  