#!/bin/bash
set -e
set -x

IPV4_REGEXP='[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}'
IPV4_NETWORK_REGEXP="$IPV4_REGEXP/[0-9]\{1,2\}"

function flat_to_ipv6 {
  # Get a flat input like fe800000000000000042acfffe110003 and output fe80::0042:acff:fe11:0003
  # This input usually comes from the ipv6_route or if_inet6 files from /proc
  input=$@
  value=""
  for item in $(echo $input | grep -o ....); do
    if [ -z $value ]; then
      value="$item";
     else
      value="$value:$item";
    fi;
  done

  # Let's remove the useless 0000 and "::"
  value=${value//0000/:};
  while $(echo $value | grep -q ":::"); do
    value=${value//::/:};
  done
  echo $value
}

function get_ip {
  # IPv4 is the default unless we specify it
  IP_LEVEL=${1:-4}
  if command -v ip &>/dev/null; then
    ip -$IP_LEVEL -o a s $NIC_MORE_TRAFFIC | awk '{ sub ("/..", "", $4); print $4 }'
  else
    case "$IP_LEVEL" in
      6)
        ip=$(flat_to_ipv6 $(grep $NIC_MORE_TRAFFIC /proc/net/if_inet6 | awk '{print $1}'))
        # IPv6 IPs should be surrounded by brackets to let ceph-monmap being happy
        echo "[$ip]"
        ;;
      *)
        grep -o "$IPV4_REGEXP" /proc/net/fib_trie | grep -vEw "^127|255$|0$" | head -1
        ;;
    esac
  fi
}

function get_network {
  # IPv4 is the default unless we specify it
  IP_LEVEL=${1:-4}
  if command -v ip &>/dev/null; then
      ip -$IP_LEVEL route show dev $NIC_MORE_TRAFFIC | grep proto | awk '{ print $1 }'
      return
  fi

  case "$IP_LEVEL" in
    6)
      line=$(grep $NIC_MORE_TRAFFIC /proc/1/task/1/net/ipv6_route | grep -v '^ff')
      base=$(echo $line | awk '{ print $1 }')
      base=$(flat_to_ipv6 $base)
      mask=$(echo $line | awk '{ print $2 }')
      echo "$base/$((16#$mask))"
      ;;
    *)
      grep -o "$IPV4_NETWORK_REGEXP" /proc/net/fib_trie | grep -vE "^127|^0" | head -1
      ;;
  esac
}

function start_mon {
  if [[ ${NETWORK_AUTO_DETECT} -eq 0 ]]; then
      if [[ -z "$CEPH_PUBLIC_NETWORK" ]]; then
        log "ERROR- CEPH_PUBLIC_NETWORK must be defined as the name of the network for the OSDs"
        exit 1
      fi

      if [[ -z "$MON_IP" ]]; then
        log "ERROR- MON_IP must be defined as the IP address of the monitor"
        exit 1
      fi
  else
    NIC_MORE_TRAFFIC=$(grep -vE "lo:|face|Inter" /proc/net/dev | sort -n -k 2 | tail -1 | awk '{ sub (":", "", $1); print $1 }')
    if [ ${NETWORK_AUTO_DETECT} -gt 1 ]; then
      MON_IP=$(get_ip ${NETWORK_AUTO_DETECT})
      CEPH_PUBLIC_NETWORK=$(get_network ${NETWORK_AUTO_DETECT})
    else # Means -eq 1
      MON_IP=$(get_ip 6)
      CEPH_PUBLIC_NETWORK=$(get_network 6)
      if [ -z "$MON_IP" ]; then
        MON_IP=$(get_ip)
        CEPH_PUBLIC_NETWORK=$(get_network)
      fi
    fi
  fi

  if [[ -z "$MON_IP" || -z "$CEPH_PUBLIC_NETWORK" ]]; then
    log "ERROR- it looks like we have not been able to discover the network settings"
    exit 1
  fi

  get_mon_config
  # If we don't have a monitor keyring, this is a new monitor
  if [ ! -e "$MON_DATA_DIR/keyring" ]; then

    if [ ! -e /etc/ceph/${CLUSTER}.mon.keyring ]; then
      log "ERROR- /etc/ceph/${CLUSTER}.mon.keyring must exist.  You can extract it from your current monitor by running 'ceph auth get mon. -o /etc/ceph/${CLUSTER}.mon.keyring' or use a KV Store"
      exit 1
    fi

    if [ ! -e /etc/ceph/monmap-${CLUSTER} ]; then
      log "ERROR- /etc/ceph/monmap-${CLUSTER} must exist.  You can extract it from your current monitor by running 'ceph mon getmap -o /etc/ceph/monmap-<cluster>' or use a KV Store"
      exit 1
    fi

    # Testing if it's not the first monitor, if one key doesn't exist we assume none of them exist
    ceph-authtool /tmp/${CLUSTER}.mon.keyring --create-keyring --import-keyring /etc/ceph/${CLUSTER}.client.admin.keyring
    ceph-authtool /tmp/${CLUSTER}.mon.keyring --import-keyring /var/lib/ceph/bootstrap-osd/${CLUSTER}.keyring
    ceph-authtool /tmp/${CLUSTER}.mon.keyring --import-keyring /var/lib/ceph/bootstrap-mds/${CLUSTER}.keyring
    ceph-authtool /tmp/${CLUSTER}.mon.keyring --import-keyring /var/lib/ceph/bootstrap-rgw/${CLUSTER}.keyring
    ceph-authtool /tmp/${CLUSTER}.mon.keyring --import-keyring /etc/ceph/${CLUSTER}.mon.keyring
    chown ceph. /tmp/${CLUSTER}.mon.keyring

    # Make the monitor directory
    mkdir -p "$MON_DATA_DIR"
    chown ceph. "$MON_DATA_DIR"

    # Prepare the monitor daemon's directory with the map and keyring
    ceph-mon --setuser ceph --setgroup ceph --mkfs -i ${MON_NAME} --monmap /etc/ceph/monmap-${CLUSTER} --keyring /tmp/${CLUSTER}.mon.keyring --mon-data "$MON_DATA_DIR"

    # Clean up the temporary key
    rm /tmp/${CLUSTER}.mon.keyring
  else
    ceph-mon --setuser ceph --setgroup ceph -i ${MON_NAME} --inject-monmap /etc/ceph/monmap-${CLUSTER} --keyring /tmp/${CLUSTER}.mon.keyring --mon-data "$MON_DATA_DIR"
    # Ignore when we timeout in most cases that means the cluster has no qorum or
    # no mons are up and running
    timeout 7 ceph mon add ${MON_NAME} "${MON_IP}:6789" || true
  fi

  log "SUCCESS"

  # start MON
  exec /usr/bin/ceph-mon ${CEPH_OPTS} -d -i ${MON_NAME} --public-addr "${MON_IP}:6789" --setuser ceph --setgroup ceph --mon-data "$MON_DATA_DIR"
}
