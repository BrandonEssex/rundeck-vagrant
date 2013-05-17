#!/usr/bin/env bash

# Exit immediately on error or undefined variable.
set -e 
set -u

# Process command line arguments.

if [ $# -ne 2 ]
then
    echo >&2 "usage: bootstrap name mysqladdr"
    exit 1
fi
NAME=$1
MYSQLADDR=$2
RUNDECK_YUM_REPO=http://repo.rundeck.org/latest.rpm

# Software install
# ----------------
#
# Utilities
# Bootstrap a fedora repo to get xmlstarlet

curl -s http://dl.fedoraproject.org/pub/epel/6/x86_64/epel-release-6-8.noarch.rpm -o epel-release.rpm -z epel-release.rpm
if ! rpm -q epel-release
then
    rpm -Uvh epel-release.rpm
fi
yum -y install xmlstarlet coreutils rsync
#
# JRE
#
yum -y install java-1.6.0
#
# Rundeck 
#
if ! rpm -q rundeck-repo
then
    rpm -Uvh "${RUNDECK_YUM_REPO}"
fi
yum -y install rundeck

# Reset the home directory permission as it comes group writeable.
# This is needed for ssh requirements.
chmod 755 ~rundeck
# Add vagrant user to rundeck group.
usermod -g rundeck vagrant

#
# Disable the firewall so we can easily access it from any host.
service iptables stop
#

# Configure rundeck.
# -----------------
#
# Configure the mysql connection.
cd /etc/rundeck
cat >rundeck-config.properties.new <<EOF
#loglevel.default is the default log level for jobs: ERROR,WARN,INFO,VERBOSE,DEBUG
loglevel.default=INFO
rdeck.base=/var/lib/rundeck
rss.enabled=true
dataSource.url = jdbc:mysql://$MYSQLADDR/rundeck?autoReconnect=true
dataSource.username=rundeckuser
dataSource.password=rundeckpassword
EOF
mv rundeck-config.properties.new rundeck-config.properties
chown rundeck:rundeck rundeck-config.properties

# Replace references to localhost with this node's name.
sed "s/localhost/$NAME/g" framework.properties > framework.properties.new
mv framework.properties.new framework.properties
chown rundeck:rundeck framework.properties

# Set the rundeck password. We need the password set
# to allow us to interactively run ssh-copy-id.
echo 'rundeck' | passwd --stdin rundeck

# Start up rundeck
# ----------------

# Check if rundeck is running and start it if necessary.
# Checks if startup message is contained by log file.
# Fails and exits non-zero if reaches max tries.

set +e; # shouldn't have to turn off errexit.

mkdir -p /var/log/vagrant
if ! /etc/init.d/rundeckd status
then
    echo "Starting rundeck..."
    (
        exec 0>&- # close stdin
        /etc/init.d/rundeckd start 
    ) &> /var/log/rundeck/service.log # redirect stdout/err to a log.

    success_msg="Started SocketConnector@"
    let count=0 max=18

    while [ $count -le $max ]
    do
        if ! grep "${success_msg}" /var/log/rundeck/service.log
        then  printf >&2 ".";#  output message.
        else  break; # successful message.
        fi
        let count=$count+1;# increment attempts count.
        [ $count -eq $max ] && {
            echo >&2 "FAIL: Execeeded max attemps "
            exit 1
        }
        sleep 10; # wait 10s before trying again.
    done
fi

echo "Rundeck started."

# Done.
exit $?