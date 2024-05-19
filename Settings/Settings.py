import json

class Settings:

    
    
    def __init__(self, settings_path) -> None:
        
        self._confFile = open(settings_path, "r")
        self._conf = json.load(self._confFile)

    
    
    

    




    