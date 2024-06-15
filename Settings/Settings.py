import json

class Settings:
    services = None
    info = None
    sniffer = None
    submitter = None
    ids = None
    proxy = None

    default_settings_Path = "Settings/settings.json"

    @staticmethod
    def load_settings():

        with open(Settings.default_settings_Path, "r") as conf_file:
            conf = json.load(conf_file)
            Settings.services = conf["services"]
            Settings.info = conf["info"]
            Settings.sniffer = conf["sniffer"]
            Settings.submitter = conf["submitter"]
            Settings.ids = conf["ids"]
            Settings.proxy = conf["proxy"]
            print("Settings loaded")
    
    @staticmethod
    def save_settings():
        with open(Settings.default_settings_Path, "w") as conf_file:
            conf = {
                "services": Settings.services,
                "info": Settings.info,
                "sniffer": Settings.sniffer,
                "submitter": Settings.submitter,
                "ids": Settings.ids,
                "proxy": Settings.proxy
            }
            json.dump(conf, conf_file, indent=2)
            print("Settings saved")
