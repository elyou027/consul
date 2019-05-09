FROM consul
RUN apk --no-cache -U add bash shadow sudo

ENV PATH              "/usr/local/bin:${PATH}"
ENV CONSUL_USER       "consul_user"
ENV CONSUL_GROUP      "consul_group"
ENV USER_ID           "1000"
ENV USER_GID          "1000"
ENV BACKUP_PATH       "/backup"
ENV CONSUL_DATA_DIR   "/data"
ENV CONSUL_BIND       "-bind 0.0.0.0"
ENV CONSUL_CLIENT     "-client 0.0.0.0"
ENV CONSUL_ALLOW_PRIVILEGED_PORTS ""
ENV BOOTSTRAP_NUM     "1"

COPY entrypoint.sh /usr/local/bin

#ENTRYPOINT ["/usr/bin/dumb-init", "--"]
ENTRYPOINT ["entrypoint.sh"]
CMD ["run_consul"]
#CMD ["entrypoint.sh", "run_consul"]
