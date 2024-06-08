import paramiko
from Settings.Settings import Settings as config # Import the Settings class from the Settings module

class Setup():

    # Attributes
    config.load_settings() # Load settings
    sshClient = paramiko.SSHClient() # ssh client
    sftpClient = None # sftp client

    def __init__(self): # Constructor
            
        pass

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

        self.sshClient.close() # Close the ssh connection
        print("SSH connection closed")

    def start_sftp(self): # Start the sftp connection
            
        self.sftpClient = self.sshClient.open_sftp() # Open the sftp connection
        print("SFTP connection established")

    def stop_sftp(self): # Close the sftp connection
            
        self.sftpClient.close() # Close the sftp connection
        self.sftpClient = None # Reset the sftp client
        print("SFTP connection closed")
    
    def upload_file(self, local_path, remote_path): # Upload a file to the server

        if self.sftpClient is None: # If the sftp connection is not open
                
            self.start_sftp()
        
        try:
            self.sftpClient.put(local_path, remote_path)
            print(f"{local_path} uploaded successfully in to {remote_path}")

        except Exception as e:
            print("Sftp Error:", str(e))
    
    def download_file(self, remote_path, local_path): # Download a file from the server

        if self.sftpClient is None: # If the sftp connection is not open
                
            self.start_sftp()

        try:

            self.sftpClient.get(remote_path, local_path)
            print(f"{remote_path} downloaded successfully in to {local_path}")

        except Exception as e:
            
            print("Sftp Error:", str(e))

    def main(self): # Main function of setup

        self.start_ssh() # start the ssh connection

        self.execute_command("echo 'Hello World'") # execute a command on the server

        self.stop_ssh()

