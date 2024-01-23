<?php
// Get the selected device from the query parameters
$device = $_GET['device'];

// Validate the device to prevent security issues
$allowedDevices = [
    'PC1', 
    'PC2',
    'PC3',
    'PC4'
    ];

if (in_array($device, $allowedDevices)) {
    // Execute the bash script with wakeonlan command
    $bashScriptPath = "/var/www/html/wake/wake_files/wake_$device.sh";

    // Capture the output of the bash script
    $output = '';
    exec("bash $bashScriptPath 2>&1", $output, $returnCode);

    if ($returnCode === 0) {
        // The command executed successfully
        echo "Success: Wake command sent for $device";
    } else {
        // The command failed
        echo "Failure: Unable to wake $device. Error: " . implode("\n", $output);
        echo "Output: " . implode("\n", $output);
    }
} else {
    echo "Invalid device";
}
?>