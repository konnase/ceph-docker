# DOCKER-VERSION 1.0.0
#
# Ceph Daemon
#
# VERSION 0.0.1

# CEPH BASE IMAGE
# CEPH VERSION: Kraken
# CEPH VERSION DETAIL: 11.1.x

FROM ubuntu:16.04
MAINTAINER Sébastien Han "seb@redhat.com"

ENV ETCDCTL_VERSION v2.2.4
ENV ETCDCTL_ARCH linux-amd64
ENV CEPH_VERSION kraken
ENV KVIATOR_VERSION 0.0.7
ENV CONFD_VERSION 0.10.0
ENV KUBECTL_VERSION v1.4.0

# Download kviator
ADD https://github.com/AcalephStorage/kviator/releases/download/v${KVIATOR_VERSION}/kviator-${KVIATOR_VERSION}-linux-amd64.zip /kviator.zip

# Download confd
ADD https://github.com/kelseyhightower/confd/releases/download/v${CONFD_VERSION}/confd-${CONFD_VERSION}-linux-amd64 /usr/local/bin/confd

# Download forego
ADD https://bin.equinox.io/c/ekMN3bCZFUn/forego-stable-linux-amd64.tgz /forego.tgz


# install prerequisites
RUN DEBIAN_FRONTEND=noninteractive apt-get update && apt-get install -y wget unzip uuid-runtime python-setuptools udev dmsetup && \
\
# install ceph and ganesha
    apt-key adv --keyserver keyserver.ubuntu.com --recv-keys 3FE869A9 && \
    echo "deb http://ppa.launchpad.net/gluster/nfs-ganesha/ubuntu xenial main" | tee /etc/apt/sources.list.d/nfs-ganesha.list && \
    echo "deb http://ppa.launchpad.net/gluster/libntirpc/ubuntu xenial main" | tee /etc/apt/sources.list.d/libntirpc.list && \
    wget -q -O- 'https://download.ceph.com/keys/release.asc' | apt-key add - && \
    echo "deb http://download.ceph.com/debian-$CEPH_VERSION/ xenial main" | tee /etc/apt/sources.list.d/ceph-$CEPH_VERSION.list && \
    apt-get update && apt-get install -y --force-yes ceph radosgw rbd-mirror nfs-ganesha nfs-ganesha-fsal && \
    apt-get clean && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/* && \
\
# Install etcdctl
    wget -q -O- "https://github.com/coreos/etcd/releases/download/${ETCDCTL_VERSION}/etcd-${ETCDCTL_VERSION}-${ETCDCTL_ARCH}.tar.gz" |tar xfz - -C/tmp/ etcd-${ETCDCTL_VERSION}-${ETCDCTL_ARCH}/etcdctl && \
    mv /tmp/etcd-${ETCDCTL_VERSION}-${ETCDCTL_ARCH}/etcdctl /usr/local/bin/etcdctl && \
\
# Install kviator
    cd /usr/local/bin && unzip /kviator.zip && chmod +x /usr/local/bin/kviator && rm /kviator.zip && \
\
# Install confd
    chmod +x /usr/local/bin/confd && mkdir -p /etc/confd/conf.d && mkdir -p /etc/confd/templates && \
\
# Install forego
    cd /usr/local/bin && tar xfz /forego.tgz && chmod +x /usr/local/bin/forego && rm /forego.tgz

# Install kubectl
ADD https://storage.googleapis.com/kubernetes-release/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl /usr/local/bin/kubectl
RUN chmod +x /usr/local/bin/kubectl

ADD https://github.com/stedolan/jq/releases/download/jq-1.5/jq-linux64 /usr/local/bin/jq
RUN chmod +x /usr/local/bin/jq

# Add bootstrap script, ceph defaults key/values for KV store
ADD *.sh ceph.defaults check_zombie_mons.py ./osd_scenarios/* /

# Add templates for confd
ADD ./confd/templates/* /etc/confd/templates/
ADD ./confd/conf.d/* /etc/confd/conf.d/

# Add volumes for Ceph config and data
VOLUME ["/etc/ceph","/var/lib/ceph", "/etc/ganesha"]

# Execute the entrypoint
WORKDIR /
ENTRYPOINT ["/entrypoint.sh"]
