#!/bin/bash
# Zatrzymuje działanie skryptu w przypadku jakiegokolwiek błędu
set -e 

echo "=== Rozpoczynam instalację K3s i Ranchera (Wersja Ubuntu z WGET) ==="

# 1. Pobranie publicznego adresu IP za pomocą wget
echo ">>> Pobieranie publicznego adresu IP..."

# Używamy serwisów API, które zawsze zwracają czysty tekst (plain text)
export VM_IP=$(wget -qO- https://api.ipify.org)

# Zabezpieczenie: jeśli ipify.org nie odpowie, używamy ident.me
if [ -z "$VM_IP" ] || [[ "$VM_IP" == *"<html"* ]]; then
  export VM_IP=$(wget -qO- https://ident.me)
fi

echo ">>> Wykryty publiczny adres IP maszyny: $VM_IP"

# 2. Konfiguracja Firewalla (UFW)
echo ">>> Konfiguracja firewalla (UFW)..."
sed -i 's/DEFAULT_FORWARD_POLICY="DROP"/DEFAULT_FORWARD_POLICY="ACCEPT"/' /etc/default/ufw

ufw allow ssh
ufw allow 80/tcp
ufw allow 443/tcp
ufw allow 6443/tcp
ufw allow from 10.42.0.0/16
ufw allow from 10.43.0.0/16

ufw --force enable
ufw reload

# 3. Instalacja k3s
echo ">>> Instalacja K3s..."
# Pobieranie i uruchamianie oficjalnego skryptu za pomocą wget
wget -qO- https://get.k3s.io | INSTALL_K3S_EXEC="server --tls-san $VM_IP" sh -

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

# Ustawienie uprawnień dla aktualnej sesji
mkdir -p ~/.kube
cp /etc/rancher/k3s/k3s.yaml ~/.kube/config
echo 'export KUBECONFIG=~/.kube/config' >> ~/.bashrc

# 4. Instalacja Helm
echo ">>> Instalacja Helm..."
wget -qO get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
chmod 700 get_helm.sh
./get_helm.sh

# 5. Instalacja cert-manager
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

# 6. Instalacja Ranchera
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
