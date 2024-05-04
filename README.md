# attack-defence-toolbox

This script goal is to setup the remote and local workspace for an A/D type CTF, we will call the remote workspace `vulnbox`.

1. **Setup of the ssh connection to the `vulnbox`**: We create new keypair for the connection to the remote host called `id_vulnbox` for the private key and `id_vulnbox.pub` for the private key, we copy the public key on the `vulnbox` using ssh-copy-id and then we disable the password authentication to the `vulnbox`.

2. **Setup of the `tulip` service**: We create a configuration file for `tulip` (named `setup_tulip.sh`) witch is copied in the `vulnbox` using `scp`, then, we execute the script on the `vulnbox` for setup `tulip` and finally we use ssh for forword the tulip service port (eg 4242) on the local machine (on port 8084), this allow us to connect to the tulip service browsing the address `http://localhost:8084/`.

3. **Setup of the Distructive Farm service**: We setup Destructive farm on the localhost

4. **Script flag**: You can know more on the script flag by running the following command on your terminal: 
```shellscript
$> bash setup.sh [-h|--help]
```

## How to run the script

for running the script, open a terminal on the folder containing the `setup.sh` file and run the following command:

```shellscript
$> bash setup.sh
```

following the execution of the script you can connect to the vulnbox with the command `ssh vulnbox`
you can find the tulip service on `http://localhost:8084/`, you can stop the ssh port forward by finding pid of the ssh connection using `ps aux | grep ssh` and then using command `kill -9 <PID>`