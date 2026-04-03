#!/bin/bash
# Zatrzymuje działanie skryptu w przypadku jakiegokolwiek błędu
set -e 

echo "=== Rozpoczynam instalację K3s i Ranchera ==="

# 1. Pobranie adresu IP na samym początku (przed utworzeniem wirtualnych interfejsów K3s)
export VM_IP=$(ip route get 1.1.1.1 | awk '{for(i=1;i<=NF;i++) if($i=="src") print $(i+1)}')
echo ">>> Wykryty zewnętrzny adres IP maszyny: $VM_IP"

# 2. Przygotowanie systemu
echo ">>> Aktualizacja pakietów i instalacja narzędzi..."
zypper --non-interactive refresh
zypper --non-interactive patch
zypper --non-interactive install -y curl tar gzip awk jq

# 3. Konfiguracja Firewalld
echo ">>> Konfiguracja firewalla..."
systemctl enable --now firewalld

# Otwarcie portów dla ruchu HTTP/HTTPS oraz API Kubernetesa
firewall-cmd --permanent --add-port=80/tcp
firewall-cmd --permanent --add-port=443/tcp
firewall-cmd --permanent --add-port=6443/tcp

# Zaufanie dla wewnętrznej sieci K3s (komunikacja podów i serwisów)
firewall-cmd --permanent --zone=trusted --add-source=10.42.0.0/16
firewall-cmd --permanent --zone=trusted --add-source=10.43.0.0/16
firewall-cmd --reload

# 4. Instalacja k3s
echo ">>> Instalacja K3s..."
curl -sfL https://get.k3s.io | sh -

export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

# Aktywne oczekiwanie na wygenerowanie konfiguracji
echo ">>> Czekam na plik konfiguracyjny klastra..."
while [ ! -f $KUBECONFIG ]; do 
  sleep 2
done

# Aktywne oczekiwanie na start API Kubernetesa
echo ">>> Czekam na gotowość API Kubernetesa..."
until kubectl get nodes &> /dev/null; do 
  sleep 2
  echo -n "."
done
echo " API działa!"

# Ustawienie uprawnień dla aktualnej sesji i konta root
mkdir -p ~/.kube
cp /etc/rancher/k3s/k3s.yaml ~/.kube/config
echo 'export KUBECONFIG=~/.kube/config' >> ~/.bashrc

# 5. Instalacja Helm
echo ">>> Instalacja Helm..."
curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
chmod 700 get_helm.sh
./get_helm.sh

# 6. Instalacja cert-manager
echo ">>> Instalacja cert-manager..."
helm repo add jetstack https://charts.jetstack.io
helm repo update
helm install cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --create-namespace \
  --set crds.enabled=true

echo ">>> Czekam na gotowość podów cert-manager..."
kubectl -n cert-manager rollout status deploy/cert-manager --timeout=300s
kubectl -n cert-manager rollout status deploy/cert-manager-webhook --timeout=300s

# 7. Instalacja Ranchera
echo ">>> Instalacja Ranchera dla domeny: rancher.${VM_IP}.nip.io"
helm repo add rancher-stable https://releases.rancher.com/server-charts/stable
helm repo update

helm install rancher rancher-stable/rancher \
  --namespace cattle-system \
  --create-namespace \
  --set hostname=rancher.${VM_IP}.nip.io \
  --set bootstrapPassword=potyczkiadminow2026 \
  --set replicas=1

echo ">>> Czekam na pełne uruchomienie Ranchera (to potrwa kilka minut)..."
kubectl -n cattle-system rollout status deploy/rancher --timeout=600s

echo "=== ZAKOŃCZONO SUKCESEM! ==="
echo "Panel logowania: https://rancher.${VM_IP}.nip.io"
echo "Login: admin"
echo "Hasło: potyczkiadminow2026"
