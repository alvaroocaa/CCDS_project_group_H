#!/bin/sh
# Prepares a node (Docker, make, NFS client + mount) and creates or joins the swarm.
#   node1:          ./swarm-up.sh manager <node1-private-ip>
#   node2, node3:   ./swarm-up.sh worker <join-token> <node1-private-ip>
set -e
NFS_SERVER=${NFS_SERVER:-172.16.0.4}
curl -fsSL https://get.docker.com | sudo sh
sudo usermod -aG docker "$USER"
sudo apt-get install -y make nfs-common
# Shared folder on every node (used by the app backup job)
sudo mkdir -p /mnt/nfs
grep -q "/mnt/nfs" /etc/fstab || \
  echo "$NFS_SERVER:/srv/nfs /mnt/nfs nfs4 defaults,_netdev 0 0" | sudo tee -a /etc/fstab
sudo mount -a
case "$1" in
  manager) sudo docker swarm init --advertise-addr "$2" ;;
  worker)  sudo docker swarm join --token "$2" "$3:2377" ;;
  *) echo "usage: $0 manager <ip> | worker <token> <manager-ip>"; exit 1 ;;
esac
