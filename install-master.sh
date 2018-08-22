for NODE in k8s-m1 k8s-m2 k8s-m3; do
    ssh ${NODE} "systemctl stop docker && systemctl stop kubelet"
    if [ "$(df -HT | grep '/var/lib/kubelet/pods' | awk '{print $7}')" ]; then
      ssh ${NODE} "umount $(df -HT | grep '/var/lib/kubelet/pods' | awk '{print $7}')"
      ssh ${NODE} "umount $(df -HT | grep '/var/lib/kubelet/pods' | awk '{print $7}')"
    fi
    
    ssh ${NODE} "rm -rf /etc/kubernetes && rm -rf ~/.kube && rm -rf /etc/etcd && rm -rf /var/lib/kubelet && rm -rf /var/log/kubernetes && rm -rf /var/lib/etcd && rm -rf /etc/systemd/system/kubelet.service.d && rm -rf /usr/local/bin/kubelet && rm -rf /usr/local/bin/kubectl"
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
      #cp -f ~/k8s/install/kubectl /usr/local/bin/kubectl
      curl -o /usr/local/bin/kubectl https://storage.googleapis.com/kubernetes-release/release/v1.11.0/bin/linux/amd64/kubectl -k
      chmod +x /usr/local/bin/kubectl
    fi"

    echo ""
    echo "== download CNI @${NODE} =="
    ssh ${NODE} "mkdir -p /opt/cni/bin && cd /opt/cni/bin"
    #wget -qO- --show-progress "${CNI_URL}/v0.7.1/cni-plugins-amd64-v0.7.1.tgz" | tar -zx
    ssh ${NODE} "export CNI_URL=https://github.com/containernetworking/plugins/releases/download
    if [ ! '$(ls -A /opt/cni/bin)' ]; then
      wget ${CNI_URL}/v0.7.1/cni-plugins-amd64-v0.7.1.tgz
      tar zxfv cni-plugins-amd64-v0.7.1.tgz -C /opt/cni/bin/
    fi"
done

echo ""
echo "== install CFSSL =="
export CFSSL_URL=https://pkg.cfssl.org/R1.2
if [ ! -x "/usr/local/sbin/cfssl" ]; then
  wget ${CFSSL_URL}/cfssl_linux-amd64 -O /usr/local/sbin/cfssl
  chmod +x /usr/local/sbin/cfssl
fi
if [ ! -x "/usr/local/sbin/cfssljson" ]; then 
  wget ${CFSSL_URL}/cfssljson_linux-amd64 -O /usr/local/sbin/cfssljson
  chmod +x /usr/local/sbin/cfssljson
fi

#echo ""
#echo "== git pull manual files =="
#git clone https://github.com/kairen/k8s-manual-files.git ~/k8s-manual-files
cd ~/k8s-manual-files/pki

echo ""
echo "== create ca & certs for etcd =="
export DIR=/etc/etcd/ssl
mkdir -p ${DIR}
cfssl gencert -initca etcd-ca-csr.json | cfssljson -bare ${DIR}/etcd-ca
cfssl gencert \
  -ca=${DIR}/etcd-ca.pem \
  -ca-key=${DIR}/etcd-ca-key.pem \
  -config=ca-config.json \
  -hostname=127.0.0.1,10.128.0.2,10.128.0.3,10.142.0.2 \
  -profile=kubernetes \
  etcd-csr.json | cfssljson -bare ${DIR}/etcd
rm -rf ${DIR}/*.csr
for NODE in k8s-m2 k8s-m3; do
    echo "--- $NODE ---"
    ssh ${NODE} " mkdir -p /etc/etcd/ssl"
    for FILE in etcd-ca-key.pem  etcd-ca.pem  etcd-key.pem  etcd.pem; do
      scp /etc/etcd/ssl/${FILE} ${NODE}:/etc/etcd/ssl/${FILE}
    done
  done

echo ""
echo "== create ca & certs for components =="
export K8S_DIR=/etc/kubernetes
export PKI_DIR=${K8S_DIR}/pki
export KUBE_APISERVER=https://10.128.0.2:6443
mkdir -p ${PKI_DIR}
cfssl gencert -initca ca-csr.json | cfssljson -bare ${PKI_DIR}/ca

cfssl gencert \
  -ca=${PKI_DIR}/ca.pem \
  -ca-key=${PKI_DIR}/ca-key.pem \
  -config=ca-config.json \
  -hostname=10.96.0.1,10.128.0.2,127.0.0.1,kubernetes.default \
  -profile=kubernetes \
  apiserver-csr.json | cfssljson -bare ${PKI_DIR}/apiserver

cfssl gencert -initca front-proxy-ca-csr.json | cfssljson -bare ${PKI_DIR}/front-proxy-ca
cfssl gencert \
  -ca=${PKI_DIR}/front-proxy-ca.pem \
  -ca-key=${PKI_DIR}/front-proxy-ca-key.pem \
  -config=ca-config.json \
  -profile=kubernetes \
  front-proxy-client-csr.json | cfssljson -bare ${PKI_DIR}/front-proxy-client
cfssl gencert \
  -ca=${PKI_DIR}/ca.pem \
  -ca-key=${PKI_DIR}/ca-key.pem \
  -config=ca-config.json \
  -profile=kubernetes \
  manager-csr.json | cfssljson -bare ${PKI_DIR}/controller-manager
kubectl config set-cluster kubernetes \
    --certificate-authority=${PKI_DIR}/ca.pem \
    --embed-certs=true \
    --server=${KUBE_APISERVER} \
    --kubeconfig=${K8S_DIR}/controller-manager.conf
kubectl config set-credentials system:kube-controller-manager \
    --client-certificate=${PKI_DIR}/controller-manager.pem \
    --client-key=${PKI_DIR}/controller-manager-key.pem \
    --embed-certs=true \
    --kubeconfig=${K8S_DIR}/controller-manager.conf
kubectl config set-context system:kube-controller-manager@kubernetes \
    --cluster=kubernetes \
    --user=system:kube-controller-manager \
    --kubeconfig=${K8S_DIR}/controller-manager.conf
kubectl config use-context system:kube-controller-manager@kubernetes \
    --kubeconfig=${K8S_DIR}/controller-manager.conf

cfssl gencert \
  -ca=${PKI_DIR}/ca.pem \
  -ca-key=${PKI_DIR}/ca-key.pem \
  -config=ca-config.json \
  -profile=kubernetes \
  scheduler-csr.json | cfssljson -bare ${PKI_DIR}/scheduler
kubectl config set-cluster kubernetes \
    --certificate-authority=${PKI_DIR}/ca.pem \
    --embed-certs=true \
    --server=${KUBE_APISERVER} \
    --kubeconfig=${K8S_DIR}/scheduler.conf
kubectl config set-credentials system:kube-scheduler \
    --client-certificate=${PKI_DIR}/scheduler.pem \
    --client-key=${PKI_DIR}/scheduler-key.pem \
    --embed-certs=true \
    --kubeconfig=${K8S_DIR}/scheduler.conf
kubectl config set-context system:kube-scheduler@kubernetes \
    --cluster=kubernetes \
    --user=system:kube-scheduler \
    --kubeconfig=${K8S_DIR}/scheduler.conf
kubectl config use-context system:kube-scheduler@kubernetes \
    --kubeconfig=${K8S_DIR}/scheduler.conf

cfssl gencert \
  -ca=${PKI_DIR}/ca.pem \
  -ca-key=${PKI_DIR}/ca-key.pem \
  -config=ca-config.json \
  -profile=kubernetes \
  admin-csr.json | cfssljson -bare ${PKI_DIR}/admin
kubectl config set-cluster kubernetes \
    --certificate-authority=${PKI_DIR}/ca.pem \
    --embed-certs=true \
    --server=${KUBE_APISERVER} \
    --kubeconfig=${K8S_DIR}/admin.conf
kubectl config set-credentials kubernetes-admin \
    --client-certificate=${PKI_DIR}/admin.pem \
    --client-key=${PKI_DIR}/admin-key.pem \
    --embed-certs=true \
    --kubeconfig=${K8S_DIR}/admin.conf
kubectl config set-context kubernetes-admin@kubernetes \
    --cluster=kubernetes \
    --user=kubernetes-admin \
    --kubeconfig=${K8S_DIR}/admin.conf
kubectl config use-context kubernetes-admin@kubernetes \
    --kubeconfig=${K8S_DIR}/admin.conf


for NODE in k8s-m1 k8s-m2 k8s-m3; do
    echo "--- $NODE ---"
    cp kubelet-csr.json kubelet-$NODE-csr.json;
    sed -i "s/\$NODE/$NODE/g" kubelet-$NODE-csr.json;
    cfssl gencert \
      -ca=${PKI_DIR}/ca.pem \
      -ca-key=${PKI_DIR}/ca-key.pem \
      -config=ca-config.json \
      -hostname=$NODE \
      -profile=kubernetes \
      kubelet-$NODE-csr.json | cfssljson -bare ${PKI_DIR}/kubelet-$NODE;
    rm kubelet-$NODE-csr.json
  done
for NODE in k8s-m1 k8s-m2 k8s-m3; do
    echo "--- $NODE ---"
    ssh ${NODE} "mkdir -p ${PKI_DIR}"
    scp ${PKI_DIR}/ca.pem ${NODE}:${PKI_DIR}/ca.pem
    scp ${PKI_DIR}/kubelet-$NODE-key.pem ${NODE}:${PKI_DIR}/kubelet-key.pem
    scp ${PKI_DIR}/kubelet-$NODE.pem ${NODE}:${PKI_DIR}/kubelet.pem
    rm ${PKI_DIR}/kubelet-$NODE-key.pem ${PKI_DIR}/kubelet-$NODE.pem
  done
for NODE in k8s-m1 k8s-m2 k8s-m3; do
    echo "--- $NODE ---"
    ssh ${NODE} "cd ${PKI_DIR} && \
      kubectl config set-cluster kubernetes \
        --certificate-authority=${PKI_DIR}/ca.pem \
        --embed-certs=true \
        --server=${KUBE_APISERVER} \
        --kubeconfig=${K8S_DIR}/kubelet.conf && \
      kubectl config set-credentials system:node:${NODE} \
        --client-certificate=${PKI_DIR}/kubelet.pem \
        --client-key=${PKI_DIR}/kubelet-key.pem \
        --embed-certs=true \
        --kubeconfig=${K8S_DIR}/kubelet.conf && \
      kubectl config set-context system:node:${NODE}@kubernetes \
        --cluster=kubernetes \
        --user=system:node:${NODE} \
        --kubeconfig=${K8S_DIR}/kubelet.conf && \
      kubectl config use-context system:node:${NODE}@kubernetes \
        --kubeconfig=${K8S_DIR}/kubelet.conf"
  done

openssl genrsa -out ${PKI_DIR}/sa.key 2048
openssl rsa -in ${PKI_DIR}/sa.key -pubout -out ${PKI_DIR}/sa.pub
rm -rf ${PKI_DIR}/*.csr \
    ${PKI_DIR}/scheduler*.pem \
    ${PKI_DIR}/controller-manager*.pem \
    ${PKI_DIR}/admin*.pem \
    ${PKI_DIR}/kubelet*.pem
for NODE in k8s-m2 k8s-m3; do
    echo "--- $NODE ---"
    for FILE in $(ls ${PKI_DIR}); do
      scp ${PKI_DIR}/${FILE} ${NODE}:${PKI_DIR}/${FILE}
    done
  done
for NODE in k8s-m2 k8s-m3; do
    echo "--- $NODE ---"
    for FILE in admin.conf controller-manager.conf scheduler.conf; do
      scp ${K8S_DIR}/${FILE} ${NODE}:${K8S_DIR}/${FILE}
    done
  done

echo ""
echo "== set master =="
cd ~/k8s-manual-files
export NODES="k8s-m1 k8s-m2 k8s-m3"
./hack/gen-configs.sh
./hack/gen-manifests.sh
for NODE in k8s-m1 k8s-m2 k8s-m3; do
    echo "--- $NODE ---"
    ssh ${NODE} "mkdir -p /var/lib/kubelet /var/log/kubernetes /var/lib/etcd /etc/systemd/system/kubelet.service.d"
    scp master/var/lib/kubelet/config.yml ${NODE}:/var/lib/kubelet/config.yml
    scp master/systemd/kubelet.service ${NODE}:/lib/systemd/system/kubelet.service
    scp master/systemd/10-kubelet.conf ${NODE}:/etc/systemd/system/kubelet.service.d/10-kubelet.conf
  done

echo ""
echo "== start kubelet at all master nodes =="
for NODE in k8s-m1 k8s-m2 k8s-m3; do
    ssh ${NODE} "systemctl enable kubelet.service && systemctl start kubelet.service"
  done

echo ""
echo "== set bootstrap ca =="
export TOKEN_ID=$(openssl rand 3 -hex)
export TOKEN_SECRET=$(openssl rand 8 -hex)
export BOOTSTRAP_TOKEN=${TOKEN_ID}.${TOKEN_SECRET}
#export KUBE_APISERVER="https://k8s-m1:6443"
kubectl config set-cluster kubernetes \
    --certificate-authority=/etc/kubernetes/pki/ca.pem \
    --embed-certs=true \
    --server=${KUBE_APISERVER} \
    --kubeconfig=/etc/kubernetes/bootstrap-kubelet.conf
kubectl config set-credentials tls-bootstrap-token-user \
    --token=${BOOTSTRAP_TOKEN} \
    --kubeconfig=/etc/kubernetes/bootstrap-kubelet.conf
kubectl config set-context tls-bootstrap-token-user@kubernetes \
    --cluster=kubernetes \
    --user=tls-bootstrap-token-user \
    --kubeconfig=/etc/kubernetes/bootstrap-kubelet.conf
kubectl config use-context tls-bootstrap-token-user@kubernetes \
    --kubeconfig=/etc/kubernetes/bootstrap-kubelet.conf

cp /etc/kubernetes/admin.conf ~/.kube/config

sleep 30;

cat <<EOF | kubectl create -f -
apiVersion: v1
kind: Secret
metadata:
  name: bootstrap-token-${TOKEN_ID}
  namespace: kube-system
type: bootstrap.kubernetes.io/token
stringData:
  token-id: "${TOKEN_ID}"
  token-secret: "${TOKEN_SECRET}"
  usage-bootstrap-authentication: "true"
  usage-bootstrap-signing: "true"
  auth-extra-groups: system:bootstrappers:default-node-token
EOF
kubectl apply -f master/resources/kubelet-bootstrap-rbac.yml
kubectl apply -f master/resources/apiserver-to-kubelet-rbac.yml
# kubectl taint nodes node-role.kubernetes.io/master="":NoSchedule --all

cd ~/k8s-manual-files

echo "===install node==="
./install-node.sh

echo "====install kube-proxy===="
./ipvs.sh
sed -i "s/\${KUBE_APISERVER}/${KUBE_APISERVER}/g" addons/kube-proxy/kube-proxy-cm.yml
kubectl delete -f addons/kube-proxy/
kubectl create -f addons/kube-proxy/
kubectl -n kube-system get po -l k8s-app=kube-proxy

echo "=======install flannel========="
kubectl create -f https://raw.githubusercontent.com/coreos/flannel/v0.10.0/Documentation/kube-flannel.yml  


eho "====install kube mestic server==="
kubectl delete -f addons/metric-server/
kubectl create -f addons/metric-server/

eho "====install kube dashboard==="
kubectl delete -f addons/dashboard/
kubectl create -f addons/dashboard/

eho "====install kube dashboard==="
kubectl delete -f addons/ingress-controller/
kubectl create -f addons/ingress-controller/

echo "====finished===="
kubectl get all --all-namespaces
kubectl get nodes