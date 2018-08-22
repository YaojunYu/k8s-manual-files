for NODE in k8s-m1 k8s-m2 k8s-m3 k8s-n1; do
    echo "====${NODE}===="
    ssh ${NODE} "rpm -import https://www.elrepo.org/RPM-GPG-KEY-elrepo.org && \
                rpm -Uvh http://www.elrepo.org/elrepo-release-7.0-2.el7.elrepo.noarch.rpm && \
                yum --disablerepo='*' --enablerepo='elrepo-kernel' list available && \
                yum -y --enablerepo=elrepo-kernel install kernel-ml.x86_64 kernel-ml-devel.x86_64 && \
                rpm -qa |grep kernel && \
                sed -i 's/GRUB_DEFAULT=saved/GRUB_DEFAULT=0/g' /etc/default/grub && \
                reboot"
done
