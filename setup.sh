#!/bin/bash
vpnfile=""
ipvulnbox=""
pswvulnbox=""
tick_length=""
tick_start=""
destructivepsw= openssl rand -hex 16
function show_help {
    echo "usage:  $BASH_SOURCE [OPTIONS]..."
    echo "Set up the enviroment for an A/D type CTF,"
    echo "Set up vpn with wireguard (given .conf file) and ssh connection to the vulnbox"
    echo "Config Destructive farm and tulip (this one on the remote machine)"
    echo "The file to specify is the path to the .conf file for wireguard"
    echo ""
    echo "Mandatory arguments to long options are mandatory for short options too."
    echo "  -i, --ip-vulnbox [vulnbox-ip]       the ip of the vulnbox"
    echo "  -p, --password [password]           the password for the ssh connection to the vulnbox"
    echo "  -v, --vpn [vpn-file]                the path to vpn configuration file"
    echo "  -g, --ip-game [game-server-ip]      the ip of the game server"
    echo "  --port-game [vpn-file]              the port on the game server to connect to"
    echo "  -l, --tick-length [vpn-file]        game protocol to use (http or tcp)"
    echo "  -l, --tick-length [vpn-file]        the legth of one tick in the game in milliseconds"
    echo "  -l, --tick-length [vpn-file]        the legth of one tick in the game in milliseconds"
    echo "  -s, --tick-start [vpn-file]         the time when tick of the game start"
    echo "  -h, --help                          display this help and exit"    
}

function create_setup_tulip {
    echo "Creating setup_tulip.sh..."
    echo "#!/bin/bash
echo Cloning repo...
git clone https://github.com/OpenAttackDefenseTools/tulip.git

echo Setting up config...
cat <<EOF > tulip/.env
FLAG_REGEX=\"[A-Z0-9]{31}=\"
TULIP_MONGO=\"mongo:27017\"
TRAFFIC_DIR_HOST=\"./services/test_pcap\"
TRAFFIC_DIR_DOCKER=\"/traffic\"
TICK_START=\"$tick_start\"
TICK_LENGTH=$tick_length
EOF

# setup config
cat <<EOF > tulip/services/api/configurations.py
#!/usr/bin/env python
import os
from pathlib import Path

traffic_dir = Path(os.getenv(\"TULIP_TRAFFIC_DIR\", \"/traffic\"))
tick_length = os.getenv(\"TICK_LENGTH\", $tick_length)
start_date = os.getenv(\"TICK_START\", \"$tick_start\")
mongo_host = os.getenv(\"TULIP_MONGO\", \"localhost:27017\")
mongo_server = f'mongodb://{mongo_host}/'
vm_ip = \"$ipvulnbox\"
services = [{\"ip\": vm_ip, \"port\": 1337, \"name\": \"cc-market\"},
            {\"ip\": vm_ip, \"port\": 5000, \"name\": \"polls\"},
            {\"ip\": vm_ip, \"port\": 8080, \"name\": \"notes\"},
            {\"ip\": vm_ip, \"port\": 8000, \"name\": \"crashair\"}]
EOF
cp tulip/services/api/configurations.py tulip/services/configurations.py
rm tulip/services/test_pcap/*

# only allow localhost access
sed -i 's/3000:3000/127.0.0.1:4242:3000/g' tulip/docker-compose.yml

echo Starting up container...
cd tulip
docker compose up --build -d


# setup monitoring script
pip3 install scp scapy
echo Starting sniffer...
mv ~/sniffer.py .
python sniffer.py -p $PWD/tulip/services/test_pcap & disown
" > setup_tulip.sh
}

ipvulnbox=127.0.0.1
echo $destructivepsw
create_setup_tulip
exit 0

TEMP=$(getopt -o i:p:v:h --long ip:,password:,vpn:,help  -n 'ad-toolbox' -- "$@")

if [ $? != 0 ] ; then echo 'Something went wrong...'>&2 ; exit 1 ; fi
eval set -- "$TEMP"
while true;
do
    case "$1" in
        -i | --ip-vulnbox ) ipvulnbox="$2"; shift ;;
        -p | --password ) pswvulnbox="$2"; shift ;;
        -v | --vpn ) vpnfile="$2"; shift ;;
        -h | --help ) show_help ; exit 0 ;;
        -- ) shift; break ;;
        * ) break ;;
    esac
    shift
done
#if the vpn file is set and validtry connecting to the vpn
if test -z $ipvulnbox;
then
    read -p 'ip of the vuln box= ' ipvulnbox
fi
#check if the ip is valid
while [[ ! $ipvulnbox =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]
do
    echo "Invalid ip address..."
    read -p 'ip of the vuln box= ' ipvulnbox
done
#check if the password is set
if test -z $pswvulnbox;
then
    read -p 'password of the vuln box= ' pswvulnbox
fi
#check if the vpn file is set and exists
if test ! -z $vpnfile; 
then
    if test ! -f $vpnfile;
    then
        echo "The file $vpnfile does not exist..." >&2
        exit 1
    fi
    $(sudo wg-quick up $vpnfile &>/dev/null ) 
    if [ $? != 0 ] ; then echo 'Something went wrong with wireguard...'>&2 ; exit 1 ; fi
else
    echo "No vpn file specified, skipping vpn setup..."
fi
#try to see if destructive farm is already there, if not clone the repo

if test ! -d ./DestructiveFarm;
then 
    echo 'Downloading Destrucive Farm...' 
    git clone https://github.com/DestructiveVoice/DestructiveFarm &>/dev/null
fi
#(re)generate the rsa key for ssh

if test ! -d ~/.ssh/id_vulnbox;
then
    rm ~/.ssh/id_vulnbox
fi
echo "Generating ssh keys ..."
ssh-keygen -t rsa -N "" -f ~/.ssh/id_vulnbox &>/dev/null
#copy the pub key on the remote machine
echo 'copy ssh pub key on the remote host...'
sshpass -p $pswvulnbox | ssh-copy-id -i ~/.ssh/id_vulnbox.pub root@$ipvulnbox &>/dev/null
if [ $? != 0 ] ; then echo 'Something went wrong...'>&2 ; exit 1 ; fi
#create config file in .ssh for semplicity
echo 'Generating ssh alias...'
#if we already use the alias vulnbox, we just update the ip otherways we create a new alias
if cat ~/.ssh/config | grep -q "host vulnbox"
then
    sed -i "/host vulnbox/{n;s/.*/    Hostname $ipvulnbox/}" ~/.ssh/config
else
    echo "host vulnbox
    Hostname $ipvulnbox
    User root
    IdentityFile ~/.ssh/id_vulnbox" >> ~/.ssh/config
fi
#disable password auth on the vulnbox
ssh vulnbox -t "sed -i -E 's/#?PasswordAuthentication (yes|no)/PasswordAuthentication no/' /etc/ssh/sshd_config" &>/dev/null
#restart ssh service
ssh vulnbox -t "systemctl reload sshd" &>/dev/null
#backup all on the remote machine
echo "backing up all on the remote host..."
ssh vulnbox -t "zip -r backup.zip *" &>/dev/null
scp vulnbox:~/backup.zip . &>/dev/null
#create the setup file for tulip
echo 'creating setup file for tulip...'
create_setup_tulip
#copy the tulip setup file on the vulnbox
echo 'installing tulip on the remote host...'
scp ./setup_tulip.sh ./sniffer.py vulnbox:~/ &>/dev/null

#run the setupfile on the remote host
ssh vulnbox -t "bash ~/setup_tulip.sh" &>/dev/null
#listen on the remote port for tulip and redirect on locahost on port 4242, run in background
ssh -f -L 8084:127.0.0.1:4242 vulnbox -N

##TODO: modify destructive farm config file
echo "all set: 
- you can connect to the vulnbox with the command \'ssh vulnbox\'
- you can find the tulip service on http://localhost:8084/, you can stop listening by finding pid using 'ps aux | grep ssh' and then using command 'kill -9 <PID>"
