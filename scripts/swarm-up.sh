#!/bin/sh
# Prepares a node (Docker, make, NFS client) and creates or joins the swarm.
#   node1:          ./swarm-up.sh manager <node1-private-ip>
#   node2, node3:   ./swarm-up.sh worker <join-token> <node1-private-ip>
set -e
curl -fsSL https://get.docker.com | sudo sh
sudo usermod -aG docker "$USER"
sudo apt-get install -y make nfs-common
case "$1" in
  manager) sudo docker swarm init --advertise-addr "$2" ;;
  worker)  sudo docker swarm join --token "$2" "$3:2377" ;;
  *) echo "usage: $0 manager <ip> | worker <token> <manager-ip>"; exit 1 ;;
esac