cd ~/k8s-manual-files
echo "====install kube-proxy===="
./ipvs.sh
sed -i "s/\${KUBE_APISERVER}/${KUBE_APISERVER}/g" addons/kube-proxy/kube-proxy-cm.yml
kubectl delete -f addons/kube-proxy/
kubectl create -f addons/kube-proxy/
kubectl -n kube-system get po -l k8s-app=kube-proxy

echo "=======install flannel========="
kubectl create -f https://raw.githubusercontent.com/coreos/flannel/v0.10.0/Documentation/kube-flannel.yml  


echo "====install kube mestic server==="
kubectl create -f addons/metric-server/

echo "====install kube dashboard==="
kubectl create -f addons/dashboard/

echo "====install kube dashboard==="
kubectl create -f addons/ingress-controller/

echo "====finished===="
kubectl get all --all-namespaces
kubectl get nodes