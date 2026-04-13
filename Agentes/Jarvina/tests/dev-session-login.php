<?php
/**
 * Dev-only helper for local QA.
 * Creates an admin session and redirects to Jarvina.
 */

if (php_sapi_name() === 'cli') {
    echo "Use this helper in browser only.\n";
    exit(0);
}

if (session_status() !== PHP_SESSION_ACTIVE) {
    session_start();
}

// Forca um admin_id numerico para compatibilidade com o backend live.
$adminId = 1;
if (!empty($_GET['admin_id']) && is_string($_GET['admin_id']) && ctype_digit($_GET['admin_id'])) {
    $adminId = (int)$_GET['admin_id'];
}
$_SESSION['admin_id'] = $adminId;
$_SESSION['admin_name'] = $_SESSION['admin_name'] ?? 'QA Local';

$redirect = '/Agentes/Jarvina/jarvina.php';
if (!empty($_GET['redirect']) && is_string($_GET['redirect'])) {
    $candidate = trim($_GET['redirect']);
    if ($candidate !== '' && str_starts_with($candidate, '/')) {
        $redirect = $candidate;
    }
}

header('Cache-Control: no-store, no-cache, must-revalidate');
header('Pragma: no-cache');
header('Location: ' . $redirect, true, 302);
exit;
