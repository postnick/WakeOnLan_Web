# WakeOnLan_Web
My personal Setup for Wake On Lan web landing page

This will have next to no utility for most people but in the internest of saving on some electricity at night and allowing for your homelab if you can enable Wake on lan on a low power device.

Use the Wake Better suggestion it's way fewer files to manage



# Tips
In most BIOS you will need to dissable Deep sleep or dissable S4/S5 Sleep for Wake on Lan to work.


The structure of your webpage is proboably like mine so for example I keep everything in 

```shell
/var/www/html/wake/
```

Each bash file needs to have the prefex 'wake_' followed by the variable name defined in the index.html file.

### Example
we have a bash file called wake_PC1.sh and wake_PC2.sh - you can give these whatever name you want.
``` HTML
    <button onclick="wakeDevice('PC1')">PC1 Text on Button</button> <br>
    <button onclick="wakeDevice('PC2')">PC2 Text on Button</button><br>
```
In the file [[wake_device.php]] you'll see this code where it appends the term 'wake_' to your PC 1
``` php 
    // $bashScriptPath = "/PATH/TO/Your/FILES/wake_files/wake_$device.sh";
    $bashScriptPath = "/var/www/html/wake/wake_files/wake_$device.sh";
```


<br>
<hr>

Credit given to Chat GPT to get me 95% of the way here. 