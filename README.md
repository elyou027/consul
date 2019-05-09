## docker-compose

```yaml
version: '2'

services:
  consul-server:
    image: antonmatyunin/consul
    container_name: consul-server
    hostname: consul.${INT_DOMAIN}
    environment:
      CONSUL_BIND: "-bind $HOST_IP"
      USER_ID: ${USER_ID}
      USER_GID: ${USER_GID}
      INT_DOMAIN: ${INT_DOMAIN}
    network_mode: "host"
    volumes:
#      - ./certs/ca.crt:/usr/local/share/ca-certificates/ca.crt
      - ./consul/data:/consul/data
      - ./consul/backup:/consul/backup
      - ./consul/config:/consul/config
    command: run_consul
```

```bash
# cat .env
USER_ID=1000
USER_GID=1000

HOST_IP=192.168.95.102
INT_DOMAIN=example.com

```