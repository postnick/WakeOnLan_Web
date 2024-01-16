<?php
// Get the selected device from the query parameters
$device = $_GET['device'];

// Validate the device to prevent security issues
// This may be uneeded
$allowedDevices = ['PC1', 'PC2','PC3','PC4'];

if (in_array($device, $allowedDevices)) {
    // Execute the bash script with wakeonlan command
    // Be sure to update the Path here to your storage location. I tried above maybe can fix later
    $bashScriptPath = "/PATH/TO/Your/FILES/wake_devices/wake_$device.sh";
    exec("bash $bashScriptPath");
    echo "Wake command sent for $device";
} else {
    echo "Invalid device";
}
?>
