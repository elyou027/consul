## docker-compose

```yaml
version: '2'

services:
  consul-server:
    container_name: consul-server
    hostname: consul.${INT_DOMAIN}
    environment:
      CONSUL_BIND: "-bind $HOST_IP"
      USER_ID: 1000
      USER_GID: 1000
      INT_DOMAIN: ${INT_DOMAIN}
    network_mode: "host"
    dns: ${HOST_IP}
    volumes:
#      - ./certs/ca.crt:/usr/local/share/ca-certificates/ca.crt
      - ./consul/data:/consul/data
      - ./consul/backup:/consul/backup
      - ./consul/config:/consul/config
    command: run_consul
```