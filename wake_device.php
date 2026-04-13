<?php
/*
 * Author: Nick
 * Date: April 13, 2026
 * Note: Overhauled by Copilot
 */

// Set the response header to indicate JSON content
header('Content-Type: application/json; charset=UTF-8');

// Check if the request method is POST; if not, return a 405 error
if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    http_response_code(405);
    echo json_encode(['status' => 'error', 'message' => 'Method not allowed']);
    exit;
}

// Retrieve and validate the 'device' parameter from POST data
$device = filter_input(INPUT_POST, 'device', FILTER_UNSAFE_RAW);
if (!is_string($device) || $device === '') {
    http_response_code(400);
    echo json_encode(['status' => 'error', 'message' => 'No device specified']);
    exit;
}

// Define an array mapping device names to their corresponding wake scripts
$allowedDevices = [
    'PC1' => 'wake_PC1.sh',
    'PC2' => 'wake_PC2.sh',
    'PC3' => 'wake_PC3.sh',
    'PC4' => 'wake_PC4.sh',

];

// Construct the full path to the wake script and verify it exists and is readable
$bashScriptPath = __DIR__ . '/wake_files/' . $allowedDevices[$device];
if (!is_file($bashScriptPath) || !is_readable($bashScriptPath)) {
    http_response_code(500);
    echo json_encode(['status' => 'error', 'message' => 'Wake script not found']);
    exit;
}

// Execute the bash script, capturing output and return code
$output = [];
$returnCode = 0;
exec('bash ' . escapeshellarg($bashScriptPath) . ' 2>&1', $output, $returnCode);

// Prepare the response array with device, status, and output
$response = [
    'device' => $device,
    'status' => $returnCode === 0 ? 'success' : 'error',
    'output' => implode("\n", $output),
];

// Set the HTTP response code and output the JSON response
http_response_code($returnCode === 0 ? 200 : 500);
echo json_encode($response, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
?>
