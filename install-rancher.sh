#!/bin/bash
# Zatrzymuje działanie skryptu w przypadku jakiegokolwiek błędu
set -e 

echo "=== Rozpoczynam instalację K3s i Ranchera ==="

# 1. Przygotowanie systemu
echo ">>> Aktualizacja pakietów i wyłączanie firewalla..."
zypper --non-interactive refresh
zypper --non-interactive up
zypper --non-interactive install -y curl tar gzip awk jq

# Upewnienie się, że firewall działa i startuje z systemem
systemctl enable --now firewalld

# 1.1 Udostępnienie niezbędnych portów na zewnątrz
# Porty 80 i 443 dla interfejsu webowego Ranchera (i obsługi certyfikatów)
firewall-cmd --permanent --add-port=80/tcp
firewall-cmd --permanent --add-port=443/tcp
# Port 6443 dla API Kubernetesa (niezbędny, aby kubectl działał poprawnie)
firewall-cmd --permanent --add-port=6443/tcp

# 1.2. Odblokowanie ruchu wewnętrznego klastra
# Domyślne podsieci K3s dla Podów (10.42.0.0/16) i Serwisów (10.43.0.0/16) 
# dodajemy do strefy zaufanej (trusted), aby mogły swobodnie ze sobą rozmawiać.
firewall-cmd --permanent --zone=trusted --add-source=10.42.0.0/16
firewall-cmd --permanent --zone=trusted --add-source=10.43.0.0/16

# 1.3. Zastosowanie nowych reguł
firewall-cmd --reload

# 2. Instalacja k3s
echo ">>> Instalacja K3s..."
curl -sfL https://get.k3s.io | sh -

# Kluczowe dla skryptu: wskazanie ścieżki do konfiguracji klastra
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

echo "Czekam 15 sekund na uruchomienie API Kubernetesa..."
sleep 15

# Konfiguracja kubectl dla roota (przydatne do późniejszego korzystania z terminala)
mkdir -p ~/.kube
cp /etc/rancher/k3s/k3s.yaml ~/.kube/config
echo 'export KUBECONFIG=~/.kube/config' >> ~/.bashrc

# 3. Instalacja Helm
echo ">>> Instalacja Helm..."
curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
chmod 700 get_helm.sh
./get_helm.sh

# 4. Instalacja cert-manager
echo ">>> Instalacja cert-manager..."
helm repo add jetstack https://charts.jetstack.io
helm repo update
helm install cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --create-namespace \
  --set crds.enabled=true

echo "Czekam na gotowość cert-manager (to może potrwać)..."
kubectl -n cert-manager rollout status deploy/cert-manager --timeout=300s
kubectl -n cert-manager rollout status deploy/cert-manager-webhook --timeout=300s

# 5. Instalacja Ranchera
export VM_IP=$(hostname -I | awk '{print $1}')
echo ">>> Instalacja Ranchera dla domeny: rancher.${VM_IP}.nip.io"

helm repo add rancher-stable https://releases.rancher.com/server-charts/stable
helm repo update

helm install rancher rancher-stable/rancher \
  --namespace cattle-system \
  --create-namespace \
  --set hostname=rancher.${VM_IP}.nip.io \
  --set bootstrapPassword=potyczkiadminow2026 \
  --set replicas=1

echo "Czekam na pełne uruchomienie Ranchera (to potrwa kilka minut)..."
kubectl -n cattle-system rollout status deploy/rancher --timeout=600s

echo "=== ZAKOŃCZONO SUKCESEM! ==="
echo "Panel logowania: https://rancher.${VM_IP}.nip.io"
echo "Login: admin"
echo "Hasło: potyczkiadminow2026"
