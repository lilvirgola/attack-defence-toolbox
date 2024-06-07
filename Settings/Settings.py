import json

class Settings:
    script = None
    tulip = None
    dFarm = None

    default_settings_Path = "Settings\settings.json"

    @staticmethod
    def load_settings():

        with open(Settings.default_settings_Path, "r") as conf_file:
            conf = json.load(conf_file)
            Settings.script = conf["script"]
            Settings.tulip = conf["tulip"]
            Settings.dFarm = conf["dFarm"]
