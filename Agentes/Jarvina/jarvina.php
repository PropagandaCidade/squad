<?php
/**
 * jarvina.php — versão estável (sem scripts globais do admin)
 * Motivo: admin_header/admin_footer estavam injetando refresh.js (ws://localhost) e checks 404,
 * o que causa reflow e “tremor” na tela, além de interferir no WS do Live.
 */

$adminConfigPath = dirname(__DIR__) . '/admin_config.php';
if (file_exists($adminConfigPath)) {
    require_once $adminConfigPath;
}

if (function_exists('check_admin_session')) {
    check_admin_session();
} else {
    if (session_status() !== PHP_SESSION_ACTIVE) {
        session_start();
    }
    if (empty($_SESSION['admin_id'])) {
        http_response_code(403);
        exit('Acesso negado. Faca login no admin.');
    }
}

$page_title = 'JARVINA AI - Link Neural';

// cache-bust mais estável (não muda toda hora): usa o mtime do index.php
$index_path = __DIR__ . '/templates/index.php';
$cache_bust = file_exists($index_path) ? (string)filemtime($index_path) : '1';

// Detecção automática de ambiente para o WebSocket (Local vs Railway)
$httpHost = strtolower((string)($_SERVER['HTTP_HOST'] ?? ''));
$hostWithScheme = (strpos($httpHost, '://') === false) ? ('http://' . $httpHost) : $httpHost;
$parsedHost = parse_url($hostWithScheme, PHP_URL_HOST);
$normalizedHost = strtolower((string)($parsedHost ?: $httpHost));

if (strpos($normalizedHost, ':') !== false) {
    $normalizedHost = explode(':', $normalizedHost, 2)[0];
}

$is_local = in_array($normalizedHost, ['localhost', '127.0.0.1', '::1'], true);
$railway_ws_url = 'wss://jarvina-production.up.railway.app/ws/live';
$local_ws_url = 'ws://127.0.0.1:8080/ws/live';
$ws_url = $railway_ws_url;

$env_ws_url = trim((string)(getenv('JARVINA_WS_URL') ?: ''));
if ($env_ws_url !== '') {
    $ws_url = $env_ws_url;
} else {
    $force_local_ws = isset($_GET['ws_local']) && $_GET['ws_local'] === '1';
    $local_backend_online = false;

    if ($is_local) {
        $socket = @fsockopen('127.0.0.1', 8080, $errno, $errstr, 0.2);
        if (is_resource($socket)) {
            $local_backend_online = true;
            fclose($socket);
        }
    }

    if ($force_local_ws || $local_backend_online) {
        $ws_url = $local_ws_url;
    }
}
?>
<!DOCTYPE html>
<html lang="pt-BR">
<head>
  <meta charset="UTF-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0" />
  <title><?php echo htmlspecialchars($page_title, ENT_QUOTES, 'UTF-8'); ?></title>

  <style>
    html, body {
      height: 100%;
      margin: 0;
      padding: 0;
      background: #050505;
      overflow: hidden; /* impede “pula-pula” de scrollbar */
      font-family: system-ui, -apple-system, Segoe UI, Roboto, Arial, sans-serif;
      color: #fff;
    }

    .topbar {
      height: 56px;
      display: flex;
      align-items: center;
      justify-content: space-between;
      padding: 0 16px;
      border-bottom: 1px solid rgba(255,255,255,0.08);
      background: rgba(0,0,0,0.55);
      backdrop-filter: blur(10px);
    }

    .brand {
      display: flex;
      align-items: center;
      gap: 10px;
      font-weight: 700;
      letter-spacing: 0.16em;
      text-transform: uppercase;
      font-size: 12px;
    }

    .dot {
      width: 8px;
      height: 8px;
      border-radius: 999px;
      background: #34d399;
      box-shadow: 0 0 18px rgba(52,211,153,0.55);
      animation: pulse 1.2s infinite ease-in-out;
    }

    @keyframes pulse {
      0%, 100% { transform: scale(1); opacity: 0.9; }
      50% { transform: scale(1.25); opacity: 1; }
    }

    .actions a {
      color: rgba(255,255,255,0.85);
      text-decoration: none;
      font-size: 12px;
      padding: 10px 12px;
      border: 1px solid rgba(255,255,255,0.12);
      border-radius: 999px;
      transition: 0.2s;
    }
    .actions a:hover {
      background: rgba(255,255,255,0.08);
    }

    .frame-wrap {
      height: calc(100% - 56px);
      width: 100%;
    }

    iframe {
      width: 100%;
      height: 100%;
      border: 0;
      display: block;
      background: #050505;
    }
  </style>
</head>

<body>
  <div class="topbar">
    <div class="brand">
      <span class="dot"></span>
      <span>JARVINA • LIVE</span>
    </div>

    <div class="actions">
      <a href="../dashboard.php">Voltar ao Admin</a>
    </div>
  </div>

  <div class="frame-wrap">
    <iframe
      src="templates/index.php?v=<?php echo urlencode($cache_bust); ?>&ws_url=<?php echo urlencode($ws_url); ?>"
      allow="microphone; clipboard-read; clipboard-write;"
      title="Jarvina Live"
    ></iframe>
  </div>
</body>
</html>
