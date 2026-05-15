#----------------------------------------------------------------------
# This script is used to setup custom user configurations in a devcontainer environment.
# Update the script with your custom configurations and it will be executed during the devcontainer build process,
# Or point it to an external script that contains your custom configurations.
#----------------------------------

iex ((New-Object System.Net.WebClient).DownloadString('https://raw.githubusercontent.com/wesleycamargo/terminal-bootstrap/refs/heads/master/terminal-setup.ps1')) 
