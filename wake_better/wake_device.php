<?php
// Get the selected device from the query parameters
$device = $_GET['device'];
$bashScriptPath = 'var/www/html/wake/wake_files'

// Validate the device to prevent security issues
$allowedDevices = ['macmini', 'op3070_win','op5000_desk','op5000_prox'];

if (in_array($device, $allowedDevices)) {
    // Execute the bash script with wakeonlan command
    $bashScriptPath = $bashScriptPath."/wake_$device.sh";
    exec("bash $bashScriptPath");
    echo "Wake command sent for $device";
} else {
    echo "Invalid device";
}
?>
