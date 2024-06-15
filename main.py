#!/usr/bin/python3
from setup import Setup
class Main:

    setup = None

    def __init__(self):
        
        self.setup = Setup()
        self.se
        

    def run(self): # Main function

        self.setup.main()

if __name__ == "__main__": # Run the main function
    main = Main()
    main.run()