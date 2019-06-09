#!/usr/bin/dumb-init  /bin/bash
set -e
#set -x

# Colorise output
RED='\033[1;31m'
NC='\033[0m'
Green='\033[1;32m'

################################################################################
USER_ID=${USER_ID:-1000}
USER_GID=${USER_GID:-1000}
CONSUL_GROUP=${CONSUL_GROUP:-consul}
CONSUL_USER=${CONSUL_USER:-consul}
CONSUL_CONFIG_DIR=${CONSUL_CONFIG_DIR:-/consul/config}
CONSUL_DATA_DIR=${CONSUL_DATA_DIR:-/consul/data}
BACKUP_DIR=${BACKUP_DIR:-/consul/backup}

##############################################################
# Creating user and group if needed
##############################################################
printf "${Green} Create group if needed ${NC}\n"

set +e

etc_group_id=`cat /etc/group | grep :$USER_GID: || echo "None"`
etc_group_name=`cat /etc/group | grep $CONSUL_GROUP || echo "None"`

if [[ "$etc_group_id" = "None" ]] && [[ "$etc_group_name" = "None" ]]
then
	printf "${Green} Create group $CONSUL_GROUP with id $USER_GID ${NC}\n"
	groupadd -g ${USER_GID} ${CONSUL_GROUP}
elif [[ "$etc_group_id" = "None" ]] && [[ "$etc_group_name" != "None" ]]
then
	printf "${Green} Group with name $CONSUL_GROUP already exist. Renaming it to conflict_group_name ${NC}\n"
  groupmod -n conflict_group_name $CONSUL_GROUP
	printf "${Green} Create group $CONSUL_GROUP with id $USER_GID ${NC}\n"
  groupadd -g ${USER_GID} ${CONSUL_GROUP}
elif [[ "$etc_group_name" = "None" ]] && [[ "$etc_group_id" != "None" ]]
then
	printf "${Green} Group with GID $USER_GID already exists. Editing it to new GID 1090 ${NC}\n"
	old_group_name=`echo ${etc_group_id} | awk -F ":" '{print $1}'`
  groupmod -g 1090 ${old_group_name}
  printf "${Green} Create group ${CONSUL_GROUP} with id ${USER_GID} ${NC}\n"
  groupadd -g ${USER_GID} ${CONSUL_GROUP}
fi

etc_passwd_id=`cat /etc/passwd | grep :${USER_ID}: || echo "None"`
etc_passwd_name=`cat /etc/passwd | grep ^${CONSUL_USER}: || echo "None"`

if [[ "$etc_passwd_id" = "None" ]] && [[ "$etc_passwd_name" = "None" ]]
then
  printf "${Green} Creating user with ID $USER_ID and name $CONSUL_USER. Assigning to group ID $USER_GID ${NC}\n"
  useradd -s /bin/bash -m -u ${USER_ID} -g ${USER_GID} ${CONSUL_USER}
elif [[ "$etc_passwd_id" != "None" ]] && [[ "$etc_passwd_name" = "None" ]]
then
  printf "${Green} User with ID $USER_ID already exists. Editing it to new ID 10067 ${NC}\n"
  usermod -g 10067 $USER_ID
  printf "${Green} Creating user with ID $USER_ID and name $CONSUL_USER. Assigning to group ID $USER_GID ${NC}\n"
  useradd -s /bin/bash -m -u $USER_ID -g $USER_GID $CONSUL_USER
elif [[ "$etc_passwd_name" != "None" ]] && [[ "$etc_passwd_id" = "None" ]]
then
  printf "${Green} User with name $CONSUL_USER already exists. Rename it to user_conflict_name ${NC}\n"
  old_user_=`echo $etc_passwd_name| awk -F ":" '{print $1}'`
  usermod -l user_conflict_name $CONSUL_USER
  printf "${Green} Creating user with ID $USER_ID and name $CONSUL_USER. Assigning to group ID $USER_GID ${NC}\n"
  useradd -s /bin/bash -m -u $USER_ID -g $USER_GID $CONSUL_USER
fi

if [[ ! -d "$CONSUL_DATA_DIR" ]]
then
	mkdir -p $CONSUL_DATA_DIR
	chown ${CONSUL_USER}:${CONSUL_GROUP} $CONSUL_DATA_DIR
fi

################################################################################
# From original docker-entrypoint.sh
# Note above that we run dumb-init as PID 1 in order to reap zombie processes
# as well as forward signals to all processes in its session. Normally, sh
# wouldn't do either of these functions so we'd leak zombies as well as do
# unclean termination of all our sub-processes.
# As of docker 1.13, using docker run --init achieves the same outcome.

# CONSUL_DATA_DIR is exposed as a volume for possible persistent storage. The
# CONSUL_CONFIG_DIR isn't exposed as a volume but you can compose additional
# config files in there if you use this image as a base, or use CONSUL_LOCAL_CONFIG
# below.
#CONSUL_CONFIG_DIR=/consul/config
# You can also set the CONSUL_LOCAL_CONFIG environemnt variable to pass some
# Consul configuration JSON without having to bind any volumes.
if [[ -n "$CONSUL_LOCAL_CONFIG" ]]; then
	echo "$CONSUL_LOCAL_CONFIG" > "$CONSUL_CONFIG_DIR/local.json"
  chown ${CONSUL_USER}:${CONSUL_GROUP} "$CONSUL_CONFIG_DIR/*"
fi

# If the user is trying to run Consul directly with some arguments, then
# pass them to Consul.
if [ "${1:0:1}" = '-' ]; then
    set -- consul "$@"
fi

# Look for Consul subcommands.
if [ "$1" = 'agent' ]; then
    shift
    set -- consul agent \
        -data-dir="$CONSUL_DATA_DIR" \
        -config-dir="$CONSUL_CONFIG_DIR" \
        $CONSUL_BIND \
        $CONSUL_CLIENT \
        "$@"
elif [ "$1" = 'version' ]; then
    # This needs a special case because there's no help output.
    set -- consul "$@"
elif consul --help "$1" 2>&1 | grep -q "consul $1"; then
    # We can't use the return code to check for the existence of a subcommand, so
    # we have to use grep to look for a pattern in the help output.
    set -- consul "$@"
fi

# If we are running Consul, make sure it executes as the proper user.
if [ "$1" = 'consul' ]; then
    # If the data or config dirs are bind mounted then chown them.
    # Note: This checks for root ownership as that's the most common case.
    if [ "$(stat -c %u ${CONSUL_DATA_DIR})" != "$(id -u consul)" ]; then
        chown ${CONSUL_USER}:${CONSUL_GROUP} ${CONSUL_DATA_DIR}
    fi
    if [ "$(stat -c %u /consul/config)" != "$(id -u consul)" ]; then
        chown ${CONSUL_USER}:${CONSUL_GROUP} /consul/config
    fi

    # If requested, set the capability to bind to privileged ports before
    # we drop to the non-root user. Note that this doesn't work with all
    # storage drivers (it won't work with AUFS).
    if [[ ! -z ${CONSUL_ALLOW_PRIVILEGED_PORTS+x} ]]; then
        setcap "cap_net_bind_service=+ep" /bin/consul
    fi

    set -- su-exec ${CONSUL_USER}:${CONSUL_GROUP} "$@"
fi
################################################################################

if [[ ! -d $BACKUP_DIR ]]
then
  mkdir -p $BACKUP_DIR
  chown ${CONSUL_USER}:${CONSUL_GROUP} $BACKUP_DIR
fi

if [[ "$1" == "run_consul" ]]
then
	printf "${Green} Starting consul daemon in server ${NC}\n"
	setcap "cap_net_bind_service=+ep" /bin/consul
    chown ${CONSUL_USER}:${CONSUL_GROUP} $CONSUL_DATA_DIR
	if [[ ! -d "$CONSUL_CONFIG_DIR" ]]
	then
		mkdir -p $CONSUL_CONFIG_DIR
		chown ${CONSUL_USER}:${CONSUL_GROUP} $CONSUL_CONFIG_DIR
	fi
#	su-exec $CONSUL_USER consul agent \
#  sudo -H -E -u $CONSUL_USER bash -c "consul agent \
    exec su-exec ${CONSUL_USER}:${CONSUL_GROUP} consul agent -server \
      -data-dir="$CONSUL_DATA_DIR" \
      -config-dir="$CONSUL_CONFIG_DIR" \
      $CONSUL_BIND \
      $CONSUL_CLIENT \
      -bootstrap-expect=${BOOTSTRAP_NUM}
elif [[ "$1" == "run_agent" ]]
then
	printf "${Green} Starting consul daemon in client mode ${NC}\n"
	setcap "cap_net_bind_service=+ep" /bin/consul
    chown ${CONSUL_USER}:${CONSUL_GROUP} $CONSUL_DATA_DIR
	if [[ ! -d "$CONSUL_CONFIG_DIR" ]]
	then
		mkdir -p $CONSUL_CONFIG_DIR
		chown ${CONSUL_USER}:${CONSUL_GROUP} $CONSUL_CONFIG_DIR
	fi
#	su-exec $CONSUL_USER consul agent \
#  sudo -H -E -u $CONSUL_USER bash -c "consul agent \
    exec su-exec ${CONSUL_USER}:${CONSUL_GROUP} consul agent \
      -data-dir="$CONSUL_DATA_DIR" \
      -config-dir="$CONSUL_CONFIG_DIR" \
      $CONSUL_BIND \
      $CONSUL_CLIENT }
elif [[ "$1" == "backup_consul" ]]
then
  f_name="consul.`date '+%Y-%m-%d_%H-%M-%S'`.snap"
  consul snapshot save ${BACKUP_DIR}/$f_name
  cp ${BACKUP_DIR}/${f_name} ${BACKUP_DIR}/consul.snap.latest
  chown ${CONSUL_USER}:${CONSUL_GROUP} ${BACKUP_DIR}/*
elif [ "$1" == "restore_consul" ]
then
  if [ -f ${BACKUP_DIR}/consul.snap.latest ]
  then
    f_name="${BACKUP_DIR}/consul.snap.latest"
  else
    for f in `ls ${BACKUP_DIR} | grep '.snap'`
    do
      # Get last of files
      f_name=${BACKUP_DIR}/$f
    done
  fi
  if [ "${f_name}none" == "none" ]
  then
    printf "${RED} Error. Do not found any snapshots in ${BACKUP_DIR} ${NC}\n"
    exit 15
  fi
  printf "${Green} Restoring $f_name ${NC}\n"
  consul snapshot restore $f_name
  printf "${Green} Done ${NC}\n"
else
	exec "$@"
fi
