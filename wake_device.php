<?php
header('Content-Type: application/json; charset=UTF-8');

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    http_response_code(405);
    echo json_encode(['status' => 'error', 'message' => 'Method not allowed']);
    exit;
}

$device = filter_input(INPUT_POST, 'device', FILTER_UNSAFE_RAW);
if (!is_string($device) || $device === '') {
    http_response_code(400);
    echo json_encode(['status' => 'error', 'message' => 'No device specified']);
    exit;
}

$allowedDevices = [
    'PC1' => 'wake_PC1.sh',
    'PC2' => 'wake_PC2.sh',
    'PC3' => 'wake_PC3.sh',
    'PC4' => 'wake_PC4.sh',

];

if (!array_key_exists($device, $allowedDevices)) {
    http_response_code(400);
    echo json_encode(['status' => 'error', 'message' => 'Invalid device']);
    exit;
}

$bashScriptPath = __DIR__ . '/wake_files/' . $allowedDevices[$device];
if (!is_file($bashScriptPath) || !is_readable($bashScriptPath)) {
    http_response_code(500);
    echo json_encode(['status' => 'error', 'message' => 'Wake script not found']);
    exit;
}

$output = [];
$returnCode = 0;
exec('bash ' . escapeshellarg($bashScriptPath) . ' 2>&1', $output, $returnCode);
$response = [
    'device' => $device,
    'status' => $returnCode === 0 ? 'success' : 'error',
    'output' => implode("\n", $output),
];

http_response_code($returnCode === 0 ? 200 : 500);
echo json_encode($response, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
?>
