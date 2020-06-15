#!/bin/sh

#############################
# WARNING: PLEASE READ README.md FIRST
#############################

source `dirname "$(readlink -f "$0")"`/conf/parameters.inc
source `dirname "$(readlink -f "$0")"`/functions/functions.inc
export LOG_FILE=$LOG_DIR/update-SSL-host_`hostname -s`.log
[[ ! -d $LOG_DIR ]] && mkdir -p $LOG_DIR && chown $CLUSTERADMIN:$CLUSTERADMIN $LOG_DIR

log "Starting update SSL certificates script"

[[ ! "$USER" == "root" ]] && log "Current user is not root, aborting" ERROR && exit 1

[[ ! -f $MANAGEMENTHOSTS_FILE ]] && log "File $MANAGEMENTHOSTS_FILE containing list of management hosts doesn't exist, aborting" ERROR && exit 1

ARCH=`uname -m`
if [ "$ARCH" != "x86_64" -a "$ARCH" != "ppc64le" ]
then
	log "Unsupported architecture (`uname -m`), aborting" ERROR
	exit 1
fi

source $INSTALL_DIR/profile.platform
export JAVA_HOME=$EGO_TOP/jre/3.8/linux-${ARCH}/
export PATH=$PATH:$JAVA_HOME/bin
export KEYTOOL_BIN=$JAVA_HOME/bin/keytool
export SECURITYUTILITY_BIN=$EGO_TOP/wlp/19.0.0.12/bin/securityUtility

log "Identify the type of current host (master, management or compute)"
determineHostType
log "Current host is $HOST_TYPE"

if [ "$HOST_TYPE" == "MASTER" ]
then
	egosh user logon -u $EGO_ADMIN_USERNAME -x $EGO_ADMIN_PASSWORD >/dev/null 2>&1
	CODE=$?
	if [ $CODE -eq 0 ]
	then
		log "Stop EGO services"
	  egosh service stop all >/dev/null
	  log "Wait for EGO services to be stopped"
	  waitForEgoServicesStopped
	  log "Stop EGO on current host"
	  egosh ego shutdown -f 2>&1 | tee -a $LOG_FILE
		log "Wait $EGO_SHUTDOWN_WAITTIME seconds to make sure all EGO processes are stopped"
		sleep $EGO_SHUTDOWN_WAITTIME
	fi

	log "Prepare hostname lists for SSL certificates"
	SSL_MANAGEMENT_HOSTNAMES_LIST=dns:$MASTERHOST
	SSL_DOMAIN=DOMAIN=.${MASTERHOST#*.}
	for MANAGEMENT_HOST in `cat $MANAGEMENTHOSTS_FILE`
	do
  	SSL_MANAGEMENT_HOSTNAMES_LIST=$SSL_MANAGEMENT_HOSTNAMES_LIST,dns:$MANAGEMENT_HOST
	done

	log "Prepare temporary directory to store SSL files generated by script on master and read by script on other hosts"
	prepareDir $SSL_TMP_DIR $CLUSTERADMIN

	log "Update tier 1 SSL certificates and keystores"
	updateSslTier1OnMaster

	log "Start EGO on this host"
	egosh ego start 2>&1 | tee -a $LOG_FILE
	log "Wait for the cluster to start"
	waitForClusterUp
else
	if [ "$HOST_TYPE" == "MANAGEMENT" ]
	then
		log "Update tier 1 SSL certificates and keystores using files generated by master host"
		updateSslTier1OnNonMaster
	fi
fi

log "Update SSL certificates script finished!" SUCCESS