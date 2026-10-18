#!/bin/sh
# Run once on node1: NFS server shared only with the swarm's private network.
set -e
SUBNET=${SUBNET:-172.16.0.0/16}
sudo apt-get update && sudo apt-get install -y nfs-kernel-server
sudo mkdir -p /srv/nfs/basic/registry /srv/nfs/basic/letsencrypt /srv/nfs/basic/certbot-www \
              /srv/nfs/app /srv/nfs/atenea /srv/nfs/stats
sudo chmod -R 777 /srv/nfs
echo "/srv/nfs $SUBNET(rw,sync,no_subtree_check,no_root_squash)" | sudo tee /etc/exports
sudo exportfs -ra
sudo systemctl enable --now nfs-kernel-server
sudo exportfs -v