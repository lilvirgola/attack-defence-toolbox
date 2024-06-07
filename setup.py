import paramiko
from Settings.Settings import Settings as config # Import the Settings class from the Settings module

class Setup():

    # Attributes
    config.load_settings() # Load settings
    sshClient = paramiko.SSHClient() # ssh client

    def execute_command(self, command): # Execute a command on the server via ssh

        stdin, stdout, stderr = self.sshClient.exec_command(command)

        print("Executing command: %s" % command)

        print(stdout.read().decode())
        print(stderr.read().decode())

    def start_ssh(self):

        # Automatically add the server's host key
        self.sshClient.set_missing_host_key_policy(paramiko.AutoAddPolicy())

        try:
            # Connect to the server
            self.sshClient.connect(config.script["hostIp"], username=config.script["ssh"]["username"], password=config.script["ssh"]["pasasword"])
            print("SSH connection established to %s" % config.script["hostIp"])

        except paramiko.AuthenticationException:

            print("SSH Authentication failed")

        except paramiko.SSHException as e:

            print("SSH connection failed:", str(e))

        except Exception as e:

            print("Error:", str(e))

    def stop_ssh(self): # Close the ssh connection

        self.sshClient.close()
        print("SSH connection closed")

    
    def main(self): # Main function

        self.start_ssh() # avvio la connessione ssh

        self.execute_command("echo 'Hello World'") # eseguo il comando

        self.stop_ssh()

    if __name__ == "__main__":

        main()
