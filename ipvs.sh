for NODE in k8s-m1 k8s-m2 k8s-m3 k8s-n1; do
    echo "====${NODE}===="
    ssh ${NODE} "yum install ipvsadm -y && ipvsadm"
    scp ipvs.modules ${NODE}:/etc/sysconfig/modules/ipvs.modules
    ssh ${NODE} "chmod 755 /etc/sysconfig/modules/ipvs.modules && bash /etc/sysconfig/modules/ipvs.modules && lsmod | grep ip_vs"
done
