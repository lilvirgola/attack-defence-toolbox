#!/bin/bash
vpnfile=''
ipvulnbox='127.0.0.1'
pswvulnbox=''
function show_help {
    echo "usage:  $BASH_SOURCE [OPTIONS]... [FILE]... "
    echo "Set up the enviroment for an A/D type CTF,"
    echo "Set up vpn with wireguard (given .conf file) and ssh connection to the vulnbox"
    echo "Config Destructive farm and tulip (this one on the remote machine)"
    echo "The file to specify is the path to the .conf file for wireguard"
    echo ""
    echo "Mandatory arguments to long options are mandatory for short options too."
    echo "  -i, --ip                    the ip of the vulnbox"
    echo "  -p, --password              the password for the ssh connection to the vulnbox"
    echo "  -h, --help                  display this help and exit"    
}
if [ $# == 0 ] ; then show_help ; exit 0 ; fi

TEMP=$(getopt -o i:p:h --long ip:,password:,help  -n 'ad-toolbox' -- "$@")

if [ $? != 0 ] ; then echo 'Something went wrong...'>&2 ; exit 1 ; fi
eval set -- "$TEMP"
while true;
do
    case "$1" in
        -i | --ip ) ipvulnbox=$2; shift ;;
        -p | --password ) pswvulnbox=$2; shift ;;
        -h | --help ) show_help ; exit 0 ;;
        -- ) shift; break ;;
        * ) break ;;
    esac
    shift
done
#try connecting to the vpn
$(sudo wg-quick up $1 &>/dev/null ) 
if [ $? != 0 ] ; then echo 'Something went wrong with wireguard...'>&2 ; exit 1 ; fi
#try to see if destructive farm is already there, if not clone the repo
if test ! -d ./DestructiveFarm 
then 
    echo 'Downloading Destrucive Farm...' 
    git clone https://github.com/DestructiveVoice/DestructiveFarm &>/dev/null
fi
#(re)generate the rsa key for ssh
if test ! -d /home/user/.ssh/id_rsa
then
    rm /home/user/.ssh/id_rsa
fi
ssh-keygen -t rsa -N "" -f /home/user/.ssh/id_rsa
#copy the pub key on the remote machine
sshpass -p $pswvulnbox ssh-copy-id root@$ipvulnbox 
if [ $? != 0 ] ; then echo 'Something went wrong'>&2 ; exit 1 ; fi
#create config file in .ssh for semplicity
echo "host vulnbox
    Hostname $ipvulnbox
    User root
    IdentityFile ~/.ssh/id_rsa" > /home/user/.ssh/config

scp ./setup_tulip.sh vulnbox:~/
ssh vulnbox -t "bash ~/setup_tulip.sh"
echo 'all set, good pwning'
