for NODE in k8s-m1 k8s-m2 k8s-m3 k8s-n1; do
    echo "====${NODE}===="
    ssh ${NODE} "yum install ipvsadm -y && \
                ipvsadm && \
                cat > /etc/sysconfig/modules/ipvs.modules <<EOF
                #!/bin/bash
                ipvs_modules='ip_vs ip_vs_lc ip_vs_wlc ip_vs_rr ip_vs_wrr ip_vs_lblc ip_vs_lblcr ip_vs_dh ip_vs_sh ip_vs_fo ip_vs_nq ip_vs_sed ip_vs_ftp nf_conntrack_ipv4'
                for kernel_module in \${ipvs_modules}; do
                    /sbin/modinfo -F filename \${kernel_module} > /dev/null 2>&1
                    if [ $? -eq 0 ]; then
                        /sbin/modprobe \${kernel_module}
                    fi
                done
                EOF && \
                chmod 755 /etc/sysconfig/modules/ipvs.modules && bash /etc/sysconfig/modules/ipvs.modules && lsmod | grep ip_vs"
done
