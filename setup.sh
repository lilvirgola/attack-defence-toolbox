#!/bin/bash
vpnfile=''
ipvulnbox=''
pswvulnbox=''
function show_help {
    echo "usage:  $BASH_SOURCE [OPTIONS]..."
    echo "Set up the enviroment for an A/D type CTF,"
    echo "Set up vpn with wireguard (given .conf file) and ssh connection to the vulnbox"
    echo "Config Destructive farm and tulip (this one on the remote machine)"
    echo "The file to specify is the path to the .conf file for wireguard"
    echo ""
    echo "Mandatory arguments to long options are mandatory for short options too."
    echo "  -i, --ip [vulnbox-ip]       the ip of the vulnbox"
    echo "  -p, --password [password]   the password for the ssh connection to the vulnbox"
    echo "  -v, --vpn  [vpn-file]       the path to vpn configuration file"
    echo "  -h, --help                  display this help and exit"    
}

TEMP=$(getopt -o i:p:v:h --long ip:,password:,vpn:,help  -n 'ad-toolbox' -- "$@")

if [ $? != 0 ] ; then echo 'Something went wrong...'>&2 ; exit 1 ; fi
eval set -- "$TEMP"
while true;
do
    case "$1" in
        -i | --ip ) ipvulnbox=$2; shift ;;
        -p | --password ) pswvulnbox=$2; shift ;;
        -v | --vpn ) pswvulnbox=$2; shift ;;
        -h | --help ) show_help ; exit 0 ;;
        -- ) shift; break ;;
        * ) break ;;
    esac
    shift
done
#if the vpn file is set and validtry connecting to the vpn
test -n $ipvulnbox #test ip empty
if [ $? == 0 ]
then
    read -p 'ip of the vuln box= ' ipvulnbox
fi
test -n $pswvulnbox #test password empty
if [ $? == 0 ]
then
    read -p 'password of the vuln box= ' pswvulnbox
fi
test -n $vpnfile #test vpn file path non zero
if [ $? != 0 ]
then
    $(sudo wg-quick up $1 &>/dev/null ) 
    if [ $? != 0 ] ; then echo 'Something went wrong with wireguard...'>&2 ; exit 1 ; fi
fi
#try to see if destructive farm is already there, if not clone the repo
test -d ./DestructiveFarm 
if [ $? != 0 ]
then 
    echo 'Downloading Destrucive Farm...' 
    git clone https://github.com/DestructiveVoice/DestructiveFarm &>/dev/null
fi
#(re)generate the rsa key for ssh
test -d ~/.ssh/id_vulnbox
if [ $? != 0 ]
then
    rm ~/.ssh/id_vulnbox
fi
echo "Generating ssh keys ..."
ssh-keygen -t rsa -N "" -f ~/.ssh/id_vulnbox &>/dev/null
#copy the pub key on the remote machine
echo 'copy ssh pub key on the remote host...'
sshpass -p $pswvulnbox ssh-copy-id -i ~/.ssh/id_vulnbox.pub root@$ipvulnbox &>/dev/null
if [ $? != 0 ] ; then echo 'Something went wrong...'>&2 ; exit 1 ; fi
#create config file in .ssh for semplicity
echo 'Generating ssh alias...'
echo "host vulnbox
    Hostname $ipvulnbox
    User root
    IdentityFile ~/.ssh/id_vulnbox" >> ~/.ssh/config
#copy the tulip setup file on the vulnbox
scp ./setup_tulip.sh vulnbox:~/
#run the setupfile on the remote host
pidssh vulnbox -t "bash ~/setup_tulip.sh"
#listen on the remote port for tulip and redirect on locahost on port 8080, run in background
ssh -L 1337:127.0.0.1:8080 vulnbox &
tulip_PID = $!

##TODO: modify destructive farm config file
echo "all set: 
- you can connect to the vulnbox with the command \'ssh vulnbox\'
- you can find the tulip service on http://localhost:8080/, you can stop listening by using command 'kill -9 $tulip_PID"