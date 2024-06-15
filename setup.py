#!/usr/bin/python3
from Settings.Settings import Settings as config # Import the Settings class from the Settings module
import os
import sys
import json
import shutil

from pathlib import Path, PosixPath

import ruamel.yaml  # pip install ruamel.yaml

class WrongArgument(Exception):
        pass
class Setup:
    blacklist=None
    yaml=None
    dirs: list[PosixPath] = []
    services_dict = {}

    def __init__(self):
        config.load_settings() # Load settings
        blacklist = ["remote_pcap_folder", "caronte", "tulip", "ctf_proxy","suricata"] # Blacklist of services
        yaml = ruamel.yaml.YAML()
        yaml.preserve_quotes = True
        yaml.indent(sequence=3, offset=1)


    def parse_dirs(self):
        """
        If the user provided arguments use them as paths to find the services.
        If not, iterate through the directories and ask for confirmation
        """
        if sys.argv[1:]:
            for dir in sys.argv[1:]:
                d = Path(dir)
                if not d.exists():
                    raise WrongArgument(f"The path {dir} doesn't exist")
                if not d.is_dir():
                    raise WrongArgument(f"The path {dir} is not a directory")
                self.dirs.append(d)
        else:
            print(f"No arguments were provided; automatically scanning for services.")
            for file in Path(".").iterdir():
                if file.is_dir() and file.stem[0] != "." and file.stem not in self.blacklist:
                    if "y" in input(f"Is {file.stem} a service? [y/N] "):
                        self.dirs.append(Path(".", file))

    def make_backup(self):
        for dir in self.dirs:
            if not Path(dir.name + f"_backup.zip").exists():
                shutil.make_archive(dir.name + f"_backup", "zip", dir)


    def parse_services(self):
        """
        If services.json is present, load it into the global dictionary.
        Otherwise, parse all the docker-compose yamls to build the dictionary and
        then save the result into services.json
        """

        for service in self.dirs:
            file = Path(service, "docker-compose.yml")
            if not file.exists():
                file = Path(service, "docker-compose.yaml")

            with open(file, "r") as fs:
                ymlfile = self.yaml.load(file)

            self.services_dict[service.stem] = {"path": str(service.resolve()), "containers": {}}

            for container in ymlfile["services"]:
                try:
                    ports_string = ymlfile["services"][container]["ports"]
                    ports_list = [p.split(":") for p in ports_string]

                    http = []
                    for port in ports_list:
                        http.append(
                            True
                            if "y"
                            in input(
                                f"Is the service {service.stem}:{port[-2]} http? [y/N] "
                            )
                            else False
                        )

                    container_dict = {
                        "target_port": [p[-1] for p in ports_list],
                        "listen_port": [p[-2] for p in ports_list],
                        "http": [h for h in http],
                    }
                    self.services_dict[service.stem]["containers"][container] = container_dict

                except KeyError:
                    print(f"{service.stem}_{container} has no ports binding")
                except Exception as e:
                    raise e
            config.services = self.services_dict
        print("Found services:")
        config.save_settings()
        for service in self.services_dict:
            print(f"\t{service}")


    def edit_services(self):
        """
        Prepare the docker-compose for each service; comment out the ports, add hostname, add the external network, add an external volume for data persistence (this alone isn't enough - it' s just for convenience since we are already here)
        """
        for service in self.services_dict:
            file = Path(self.services_dict[service]["path"], "docker-compose.yml")
            if not file.exists():
                file = Path(self.services_dict[service]["path"], "docker-compose.yaml")
            print(file.exists())
            if not file.exists():
                file = Path(self.services_dict[service]["path"], "compose.yml")
            if not file.exists():
                file = Path(self.services_dict[service]["path"], "compose.yaml")

            with open(file, "r") as fs:
                ymlfile = self.yaml.load(file)

            for container in self.services_dict[service]["containers"]:
                try:
                    # Add a comment with the ports
                    target_ports = self.services_dict[service]["containers"][container][
                        "target_port"
                    ]
                    listen_ports = self.services_dict[service]["containers"][container][
                        "listen_port"
                    ]
                    ports_string = "ports: "
                    for target, listen in zip(target_ports, listen_ports):
                        ports_string += f"- {listen}:{target} "

                    ymlfile["services"].yaml_add_eol_comment(ports_string, container)

                    # Remove the actual port bindings
                    try:
                        ymlfile["services"][container].pop("ports")
                    except KeyError:
                        pass  # this means we had already had removed them

                    # Add hostname
                    hostname = f"{service}_{container}"
                    if "hostname" in ymlfile["services"][container]:
                        print(
                            f"[!] Error: service {service}_{container} already has a hostname. Skipping this step, review it manually before restarting."
                        )
                    else:
                        ymlfile["services"][container]["hostname"] = hostname

                except Exception as e:
                    json.dump(ymlfile, sys.stdout, indent=2)
                    print(f"\n{container = }")
                    raise e

                # TODO: Add restart: always

                # add external network
                net = {"default": {"name": "ctf_network", "external": True}}
                if "networks" in ymlfile:
                    if "default" not in ymlfile["networks"]:
                        ymlfile["networks"].append(net)
                    else:
                        print(
                            f"[!] Error: service {service} already has a default network. Skipping this step, review it manually before restarting."
                        )
                else:
                    ymlfile["networks"] = net

                # write file
                with open(file, "w") as fs:
                    self.yaml.dump(ymlfile, fs)


    def configure_proxy(self):
        """
        Properly configure both the proxy's docker-compose with the listening ports and the config.json with all the services.
        We can't automatically configure ssl for now, so it's better to set https services as not http so they keep working at least. Manually configure the SSL later and turn http back on.
        """
        # Download ctf_proxy
        if not Path(f"./{config.proxy["dir_name"]}").exists():
            os.system(f"git clone {config.proxy["repo"]}")

        with open("./ctf_proxy/docker-compose.yml", "r") as file:
            ymlfile = self.yaml.load(file)

        # Add all the ports to the compose
        ports = []
        for service in self.services_dict:
            for container in self.services_dict[service]["containers"]:
                for port in self.services_dict[service]["containers"][container]["listen_port"]:
                    ports.append(f"{port}:{port}")
        # ymlfile["services"]["proxy"]["ports"] = ports
        ymlfile["services"]["nginx"]["ports"] = ports
        with open("./ctf_proxy/docker-compose.yml", "w") as fs:
            self.yaml.dump(ymlfile, fs)

        # Proxy config.json
        print("Remember to manually edit the config for SSL")
        services = []
        for service in self.services_dict:
            for container in self.services_dict[service]["containers"]:
                name = f"{service}_{container}"
                target_ports = self.services_dict[service]["containers"][container][
                    "target_port"
                ]
                listen_ports = self.services_dict[service]["containers"][container][
                    "listen_port"
                ]
                http = self.services_dict[service]["containers"][container]["http"]
                for i, (target, listen) in enumerate(zip(target_ports, listen_ports)):
                    services.append(
                        {
                            "name": name + str(i),
                            "target_ip": name,
                            "target_port": int(target),
                            "listen_port": int(listen),
                            "http": http[i],
                        }
                    )

        with open("./ctf_proxy/proxy/config/config.json", "r") as fs:
            proxy_config = json.load(fs)
        proxy_config["services"] = services
        with open("./ctf_proxy/proxy/config/config.json", "w") as fs:
            json.dump(proxy_config, fs, indent=2)


    def restart_services(self):
        """
        Make sure every service is off and then start them one by one after the proxy
        """

        for service in self.services_dict:
            os.system(
                f"bash -c '!(docker compose --file {self.services_dict[service]['path']}/docker-compose.yml down) && docker compose --file {self.services_dict[service]['path']}/docker-compose.yaml down'"
            )

        os.system(
            f"bash -c 'docker compose --file ctf_proxy/docker-compose.yml restart; docker compose --file ctf_proxy/docker-compose.yml up -d'"
        )

        for service in self.services_dict:
            os.system(
                f"bash -c '!(docker compose --file {self.services_dict[service]['path']}/docker-compose.yml up -d) && docker compose --file {self.services_dict[service]['path']}/docker-compose.yaml up -d'"
            )
    
    def configure_sniffer(self):
        # Download sniffer eg. tulip
        if not Path(f"./{config.sniffer["dir_name"]}").exists():
            os.system(f"git clone {config.sniffer["repo"]}")
        with open(f"./{config.sniffer["dir_name"]}/.env", "w") as fs:
            fs.write(f"FLAG_REGEX={config.info['flag_regex']}")
            fs.write("TULIP_MONGO=\"mongo:27017\"\n"+"TRAFFIC_DIR_HOST=\"./services/test_pcap\"\n"+"TRAFFIC_DIR_DOCKER=\"/traffic\"")
            fs.write(f"TICK_START={config.info['tick_start']}")
            fs.write(f"TICK_LENGTH={config.info['tick_length']}")
        with open(f"./{config.sniffer["dir_name"]}/services/api/configurations.py", "w") as fs:
            fs.write("#!/usr/bin/env python \n"+"import os\n"+"from pathlib import Path")
            fs.write("traffic_dir = Path(os.getenv(\"TULIP_TRAFFIC_DIR\", \"/traffic\"))")
            fs.write(f"tick_length = int(os.getenv(\"TICK_LENGTH\",{config.info['tick_length']}))")
            fs.write(f"start_date = int(os.getenv(\"TICK_START\", {config.info['tick_start']}))")
            fs.write("mongo_server = f'mongodb://{mongo_host}/'")
            fs.write(f"vm_ip = {config.info['vm_ip']}")
            fs.write("services = [")
            for service in config.services:
                for sub_service in config.services[service]['containers']:
                    fs.write("{"+f"\"ip\": vm_ip, \"port\": {config.services[service]['containers'][sub_service]['listen_port']} \"name\": {service if service==sub_service else service+"_"+sub_service}"+"},")
            fs.write("]")
        os.system("cp tulip/services/api/configurations.py tulip/services/configurations.py")
        os.system("rm tulip/services/test_pcap/*")
        os.system(f"sed -i 's/3000:3000/127.0.0.1:{config.sniffer["port"]}:3000/g' tulip/docker-compose.yml")
        print(f"Starting {config.sniffer['dir_name']} docker...")
        os.system(f"docker compose -f ./{config.sniffer["dir_name"]}/*.y* up -d")
        os.system(f"pip3 install scp scapy")
        print(f"Starting sniffer...")
        os.system(f"mv sniffer.py {config.sniffer['dir_name']}/")
        os.system(f"python3 {config.sniffer['dir_name']}/sniffer.py & disown")

    def configure_submitter(self):
        # Download submitter eg. DFarm
        if not Path(f"./{config.submitter["dir_name"]}").exists():
            os.system(f"git clone {config.submitter["repo"]}")

    def configure_ids(self):
        # Download ids eg. suricata
        if not Path(f"./{config.ids["dir_name"]}").exists():
            os.system(f"git clone {config.ids["repo"]}")

    def main(self): # Main function of setup
        self.parse_dirs()
        self.parse_services()
        self.make_backup()
        self.edit_services()
        self.configure_proxy()
        
        confirmation = input(
            "You are about to restart all your services! Make sure that no catastrophic configuration error has occurred.\nPress Enter to continue"
        )
        self.restart_services()