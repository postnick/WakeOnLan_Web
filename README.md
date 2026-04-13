# Wake_on_lan

My personal Setup for Wake On Lan web landing page

This will have next to no utility for most people but in the internest of saving on some electricity at night and allowing for your homelab if you can enable Wake on lan on a low power device.

Use the Wake Better suggestion it's way fewer files to manage


## Tips
In most BIOS you will need to dissable Deep sleep or dissable S4/S5 Sleep for Wake on Lan to work.


The structure of your webpage is proboably like mine so for example I keep everything in 

```bash
    /var/www/html/wake/
```

Each bash file needs to have the prefex 'wake_' followed by the variable name defined in the index.html file.
<hr>

### Examples
we have a bash file called wake_PC1.sh and wake_PC2.sh - you can give these whatever name you want.


<hr>


## Requirements
- Web Server, I think Apache 2
- PHP on device
- wakeonlan on device
- security at your own risk maybe don't expose to the net. 
<br>
<hr>


###  Help from Chat GPT

The code for getting the update pushed to the web server. 

```bash
    #!/bin/bash
    cd /opt/Wake_on_lan || exit
    git pull
    rsync -av --delete ./ /var/www/html/wake --exclude .git
    chown -R www-data:www-data /var/www/html
```

<br><br>
<hr>

### Transprancy with useage of AI
This project was created with the help of AI, specifically ChatGPT. The AI assisted in generating code snippets, providing suggestions for structuring the project, and offering guidance on best practices for implementing Wake on LAN functionality. The AI's contributions were instrumental in shaping the overall design and functionality of the project, making it more efficient and user-friendly. 

I did however review and test all of the code to make sure it actually works in my implementations. 

### License
No license, do whatever you want with it. but in the spirit of open source and sharing, if you make improvements or have suggestions please share them back with me.