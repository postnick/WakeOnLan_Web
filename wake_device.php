<?php
// Get the selected device from the query parameters
$device = $_GET['device'];

// Validate the device to prevent security issues
$allowedDevices = ['PC1', 'PC2','PC3','PC4'];

if (in_array($device, $allowedDevices)) {
    // Execute the bash script with wakeonlan command
    // Be sure to update the Path here to your storage location
    $bashScriptPath = "/PATH/TO/Your/FILES/wake_files/wake_$device.sh";
    exec("bash $bashScriptPath");
    echo "Wake command sent for $device";
} else {
    echo "Invalid device";
}
?>