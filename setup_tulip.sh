#!/bin/bash
echo Cloning repo...
git clone https://github.com/OpenAttackDefenseTools/tulip.git

echo Setting up config...
cat <<EOF > tulip/.env
FLAG_REGEX="[A-Z0-9]{31}="
TULIP_MONGO="mongo:27017"
TRAFFIC_DIR_HOST="./services/test_pcap"
TRAFFIC_DIR_DOCKER="/traffic"
TICK_START="2024-04-20T08:00+02:00"
TICK_LENGTH=120000
EOF

# setup config
cat <<EOF > tulip/services/api/configurations.py
#!/usr/bin/env python
import os
from pathlib import Path

traffic_dir = Path(os.getenv("TULIP_TRAFFIC_DIR", "/traffic"))
tick_length = os.getenv("TICK_LENGTH", 2*60*1000)
start_date = os.getenv("TICK_START", "2018-06-27T13:00+02:00")
mongo_host = os.getenv("TULIP_MONGO", "localhost:27017")
mongo_server = f'mongodb://{mongo_host}/'
vm_ip = "10.60.64.1"
services = [{"ip": vm_ip, "port": 1337, "name": "cc-market"},
			{"ip": vm_ip, "port": 5000, "name": "polls"},
			{"ip": vm_ip, "port": 8080, "name": "notes"},
			{"ip": vm_ip, "port": 8000, "name": "crashair"}]
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
cat <<EOF > ./sniffer.py
import argparse
import os

from paramiko import SSHClient, AutoAddPolicy
from signal import signal, SIGINT
from datetime import datetime
from scp import SCPClient
from scapy.all import *
from sys import exit

DO_PRINT = True
MAX_SESSION_USAGE = 100

def get_timestamp():
	return datetime.now().strftime("%Y-%m-%d-%H-%M-%S")

def print_log(*args, **kwargs):
	if DO_PRINT:
		print(*args, **kwargs)

def get_ssh_client():
	ssh = SSHClient()
	# Ricordati di connetterti manualmente almeno una volta!
	ssh.set_missing_host_key_policy(AutoAddPolicy())
	ssh.connect(args.ip, username=args.user, key_filename="/root/.ssh/vulnbox")
	return ssh

# Argument parser
parser = argparse.ArgumentParser(description="Sniffa pacchetti su un'interfaccia di rete e salvali in un file.")
parser.add_argument('-i', '--interface', type=str, default='game', help="l'interfaccia di rete su cui effettuare lo sniffing (default: eth0)")
parser.add_argument('-t', '--timeout', type=int, default=30, help='secondi per lo sniffing (default: 30 secondi)')
parser.add_argument('-f', '--filter', type=str, default=None, help='porte su cui stare in ascolto. Es. "1234,8080,6969" (default: tutte)')
parser.add_argument('-p', '--folderpath', type=str, default='/tmp/tulip/services/captures/', help='Il percorso della cartella su cui caricare i .pcap')
parser.add_argument('-m', '--maxfoldersize', type=int, default=1024*1024*100, help='La dimensione massima della cartella in byte (default: 100 MB)') # 100 MB
parser.add_argument('-u', '--user', type=str, default=None, help='Nome utente della connessione ssh. Se non settato salva i file in locale')
parser.add_argument('-a', '--ip', type=str, default=None, help='Indirizzo ip della connessione ssh. Se non settato salva i file in locale')

# Esempio di filtro BPF
# port 42069 or port 1337

args = parser.parse_args()

args.folderpath = args.folderpath + '/' if args.folderpath[-1] != '/' else args.folderpath

# Se si vuole salvare in remoto, bisogna creare una connessione ssh
if (args.ip is not None) and (args.user is not None):
	ssh = get_ssh_client()
	session_usage_counter = 0

# Nel caso si voglia inserire il filtro hardcoded
# args.filter = "port 80"
# Lista per contenere i pacchetti catturati
captured_packets = []

# Funzione per gestire la ricezione di SIGINT ed uscire
# Se comunque non si riesce ad uscire dal programma con CTRL+C,
# prova a usare CTRL+Z o CTRL+\
def exit_handler(signal_received, frame):
	print_log("Processo terminato")
	exit(0)

# Funzione per aggiungere i paccchetti sniffati
# Possono essere aggiunte altre funzioni per filtrare i pacchetti
def packet_handler(packet):
	captured_packets.append(packet)

def get_bpf_from_ports(raw_ports):
	port_list = raw_ports.split(',')
	
	# Remove all empty elements of the array
	port_list = list(filter(lambda port: port != "", port_list))

	# Add the "port" keyword to each port
	port_list = list(map(lambda x: "port " + x, port_list))

	# Join all the ports with "or"
	bpf = " or ".join(port_list)

	return bpf


if __name__ == "__main__":

	print_log("Inizio cattura pacchetti")
	if (args.ip is not None) and (args.user is not None):
		print_log(f"Salvataggio in remoto su {args.user}@{args.ip}")
	else:
		print_log("Salvataggio in locale")

	signal(SIGINT, lambda *args: exit_handler(*args))

	filter_bpf = args.filter
	if filter_bpf is not None:
		filter_bpf = get_bpf_from_ports(args.filter)
		print("Applico filtro BPF: " + filter_bpf)

	while True:

		# Inizia a fare lo sniffing per i pacchetti
		sniff(iface=args.interface, prn=packet_handler, filter=filter_bpf, timeout=args.timeout)
		filename = f"log_{get_timestamp()}.pcap"
		wrpcap(args.folderpath + filename, captured_packets)
		captured_packets.clear()
		print_log(f"salvato {filename}")
		if (args.ip is not None) and (args.user is not None):
			
			session_usage_counter = (session_usage_counter + 1) % MAX_SESSION_USAGE

			# Ogni 100 sessioni, chiudi la connessione e riaprila
			if session_usage_counter % MAX_SESSION_USAGE == 0:
				print("Refreshing della connessione...")
				ssh.close()
				ssh = get_ssh_client()
				print("Connessione refreshata...")


			with SCPClient(ssh.get_transport()) as scp:
				scp.put(args.folderpath + filename, remote_path=f'/tmp/tulip/services/captures')
			os.remove(args.folderpath + filename)
		else:
			# Controlla se la cartella è troppo grande
			folder_size = sum(os.path.getsize(os.path.join(args.folderpath, f)) for f in os.listdir(args.folderpath) if os.path.isfile(os.path.join(args.folderpath, f)))
			if folder_size >= args.maxfoldersize:
				print_log("Dimensione massima raggiunta!")
				files = os.listdir(args.folderpath)

				# Ordine alfabetico!!
				files.sort()

				# Cancello il primo 20% dei file
				num_files_to_delete = int(len(files) * 0.20)
				for i in range(num_files_to_delete):
					if files[i] == sys.argv[0]:
						continue

					file_to_delete = os.path.join(args.folderpath, files[i])
					os.remove(file_to_delete)
					print_log(f"Deleted file: {file_to_delete}")
EOF

echo Starting sniffer...
python sniffer.py -p $PWD/tulip/services/test_pcap & disown
