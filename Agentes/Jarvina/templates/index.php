<?php
$adminConfigPath = dirname(__DIR__, 2) . '/admin_config.php';
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

$adminToken = isset($_SESSION['admin_id']) ? trim((string)$_SESSION['admin_id']) : '';
$wsUrlInput = isset($_GET['ws_url']) ? trim((string)$_GET['ws_url']) : '';

function jarvina_is_allowed_ws_url($url)
{
    if ($url === '') {
        return false;
    }

    $localPattern = '#^ws://(?:localhost|127\.0\.0\.1)(?::\d{1,5})?/ws/live$#i';
    $railwayPattern = '#^wss://jarvina-production\.up\.railway\.app/ws/live$#i';

    return (bool)preg_match($localPattern, $url) || (bool)preg_match($railwayPattern, $url);
}

$wsUrl = jarvina_is_allowed_ws_url($wsUrlInput)
    ? $wsUrlInput
    : 'wss://jarvina-production.up.railway.app/ws/live';

if (!function_exists('jarvina_asset_version')) {
    function jarvina_asset_version($fileName)
    {
        $path = __DIR__ . '/' . $fileName;
        return file_exists($path) ? (string)filemtime($path) : '1';
    }
}

$mediaHandlerVersion = jarvina_asset_version('media-handler.js');
$geminiClientVersion = jarvina_asset_version('gemini-client.js');
$mainVersion = jarvina_asset_version('main.js');
?>
<!DOCTYPE html>
<html lang="pt-br">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>JARVINA LIVE</title>

    <script src="https://cdn.tailwindcss.com"></script>
    <script src="https://unpkg.com/lucide@0.542.0/dist/umd/lucide.min.js"></script>

    <style>
        @import url('https://fonts.googleapis.com/css2?family=JetBrains+Mono:wght@300;400;700&display=swap');
        body { font-family: 'JetBrains Mono', monospace; background-color: #050505; color: #fff; overflow: hidden; margin: 0; }

        .scanline {
            position: fixed; top: 0; left: 0; width: 100%; height: 100%;
            background: linear-gradient(to bottom, rgba(18, 16, 16, 0) 50%, rgba(0, 0, 0, 0.1) 50%),
                        linear-gradient(90deg, rgba(16, 185, 129, 0.02), rgba(16, 185, 129, 0.01), rgba(16, 185, 129, 0.02));
            background-size: 100% 4px, 3px 100%; pointer-events: none; z-index: 100;
        }

        .orb-glow { box-shadow: 0 0 60px 10px rgba(16, 185, 129, 0.2); transition: all 0.5s ease-in-out; }
        .orb-listening { animation: orb-breath 2s infinite alternate; background: rgba(16, 185, 129, 0.15) !important; border-color: rgba(16, 185, 129, 0.5) !important; }
        .orb-speaking { animation: orb-talk 0.2s infinite alternate; background: rgba(16, 185, 129, 0.6) !important; box-shadow: 0 0 90px 40px rgba(16, 185, 129, 0.5); }

        @keyframes orb-breath { from { transform: scale(1); } to { transform: scale(1.05); } }
        @keyframes orb-talk { from { transform: scale(1); } to { transform: scale(1.02); } }

        .text-glow { text-shadow: 0 0 10px rgba(16, 185, 129, 0.4); }

        /* --- VU METER --- */
        .vu-wrap {
            width: 100%;
            max-width: 420px;
            margin: 14px auto 0 auto;
        }
        .vu-bar {
            height: 10px;
            border-radius: 999px;
            background: rgba(255,255,255,0.08);
            border: 1px solid rgba(255,255,255,0.10);
            overflow: hidden;
            position: relative;
        }
        .vu-fill {
            height: 100%;
            width: 0%;
            background: linear-gradient(90deg,
                rgba(16,185,129,0.65),
                rgba(16,185,129,0.95),
                rgba(245,158,11,0.95),
                rgba(239,68,68,0.95)
            );
            border-radius: 999px;
            transition: width 60ms linear;
        }
        .vu-meta {
            margin-top: 8px;
            display: flex;
            justify-content: space-between;
            font-size: 10px;
            letter-spacing: 0.22em;
            text-transform: uppercase;
            color: rgba(161,161,170,1); /* zinc-400 */
        }
        .vu-pill {
            display: inline-flex;
            align-items: center;
            gap: 8px;
            padding: 6px 10px;
            border-radius: 999px;
            border: 1px solid rgba(255,255,255,0.10);
            background: rgba(0,0,0,0.25);
        }
        .vu-dot {
            width: 8px; height: 8px; border-radius: 999px;
            background: rgba(113,113,122,1); /* zinc-500 */
        }
        .vu-dot.on {
            background: rgba(16,185,129,1);
            box-shadow: 0 0 14px rgba(16,185,129,0.55);
        }

        /* --- TELEMETRY PANEL --- */
        .telemetry-grid {
            margin-top: 12px;
            display: grid;
            grid-template-columns: repeat(2, minmax(0, 1fr));
            gap: 8px;
            width: 100%;
            max-width: 560px;
        }
        .telemetry-item {
            display: flex;
            align-items: center;
            justify-content: space-between;
            gap: 10px;
            border: 1px solid rgba(255,255,255,0.12);
            background: rgba(10, 10, 10, 0.45);
            border-radius: 12px;
            padding: 8px 10px;
            min-height: 38px;
        }
        .telemetry-label {
            font-size: 9px;
            text-transform: uppercase;
            letter-spacing: 0.18em;
            color: rgba(161,161,170,1);
        }
        .telemetry-value {
            font-size: 10px;
            text-transform: uppercase;
            letter-spacing: 0.08em;
            color: rgba(167,243,208,1);
            font-weight: 700;
            text-align: right;
        }
        @media (max-width: 560px) {
            .telemetry-grid {
                grid-template-columns: 1fr;
            }
        }
    </style>
</head>

<body class="relative w-full h-screen flex items-center justify-center">
    <div class="scanline"></div>

    <div class="absolute top-0 left-0 w-full h-full bg-gradient-to-br from-black via-zinc-950 to-black opacity-90"></div>

    <div class="relative z-10 w-full max-w-xl px-6 flex flex-col items-center">

        <!-- HEADER -->
        <div class="w-full flex items-center justify-between mb-10">
            <div class="flex items-center gap-3">
                <div class="w-2 h-2 rounded-full bg-emerald-400 animate-pulse"></div>
                <span class="text-[11px] tracking-[0.35em] text-emerald-200 uppercase font-bold text-glow">JARVINA LIVE</span>
            </div>
            <div class="text-[10px] tracking-[0.25em] text-zinc-400 uppercase">VOICE HUB</div>
        </div>

        <!-- CENTRAL ORB -->
        <div id="orb" class="w-44 h-44 bg-zinc-900 border border-white/10 rounded-full orb-glow flex items-center justify-center transition-all duration-300">
            <i id="orb-icon" data-lucide="mic-off" class="w-14 h-14 text-emerald-300"></i>
        </div>

        <!-- STATUS -->
        <div class="mt-8 text-center w-full">
            <div id="status-container" class="flex items-center justify-center gap-2 mb-2">
                <div id="status-led" class="w-2 h-2 rounded-full bg-zinc-600"></div>
                <div id="status-text" class="text-[9px] uppercase tracking-widest font-bold text-zinc-500">Standby</div>
            </div>

            <div id="main-display" class="text-sm text-zinc-200 leading-relaxed min-h-[52px] px-4">
                Clique em <span class="text-emerald-300 font-bold">CONEXÃO LIVE</span> para iniciar.
            </div>

            <!-- ✅ VU METER (VISUAL DA SUA VOZ) -->
            <div class="vu-wrap">
                <div class="vu-bar">
                    <div id="vu-fill" class="vu-fill"></div>
                </div>

                <div class="vu-meta">
                    <div class="vu-pill">
                        <span id="vu-dot" class="vu-dot"></span>
                        <span>Mic Level</span>
                    </div>
                    <div class="vu-pill">
                        <span id="mic-ok" class="text-zinc-400">MIC: --</span>
                    </div>
                </div>
            </div>

            <div id="telemetry-panel" class="telemetry-grid" aria-live="polite">
                <div class="telemetry-item">
                    <span class="telemetry-label">Mic Status</span>
                    <span id="telemetry-mic" class="telemetry-value">STANDBY</span>
                </div>
                <div class="telemetry-item">
                    <span class="telemetry-label">Bytes</span>
                    <span id="telemetry-bytes" class="telemetry-value">0 B</span>
                </div>
                <div class="telemetry-item">
                    <span class="telemetry-label">Chunks</span>
                    <span id="telemetry-chunks" class="telemetry-value">0</span>
                </div>
                <div class="telemetry-item">
                    <span class="telemetry-label">Model Response</span>
                    <span id="telemetry-model" class="telemetry-value">AGUARDANDO</span>
                </div>
            </div>

            <div id="user-transcript" class="text-[11px] text-zinc-500 mt-3 min-h-[18px] px-4"></div>
        </div>

        <!-- BUTTON -->
        <div class="w-full mt-10">
            <button id="live-btn" class="w-full py-6 bg-white text-black rounded-3xl font-bold text-xs tracking-[0.3em] flex items-center justify-center gap-4 hover:bg-emerald-400 transition-all shadow-[0_0_30px_rgba(255,255,255,0.1)] active:scale-95">
                <i data-lucide="zap" class="w-5 h-5"></i> CONEXÃO LIVE
            </button>
        </div>

        <!-- FOOTER -->
        <div class="mt-10 text-[10px] text-zinc-600 tracking-widest uppercase">
            MODE: LIVE • WS_SECURE • LATENCY: LOW
        </div>

        <!-- SCRIPTS (cache bust por mtime estavel) -->
        <script>
            window.JARVINA_CONFIG = {
                adminToken: <?php echo json_encode($adminToken, JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE); ?>,
                wsUrl: <?php echo json_encode($wsUrl, JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE); ?>
            };
        </script>
        <script src="media-handler.js?v=<?php echo urlencode($mediaHandlerVersion); ?>"></script>
        <script src="gemini-client.js?v=<?php echo urlencode($geminiClientVersion); ?>"></script>
        <script src="main.js?v=<?php echo urlencode($mainVersion); ?>"></script>

        <script>
            lucide.createIcons();

            // O main.js chama window.updateUI(true/false)
            window.updateUI = function(isLive) {
                const statusLed = document.getElementById("status-led");
                const statusText = document.getElementById("status-text");
                const orb = document.getElementById("orb");
                const orbIcon = document.getElementById("orb-icon");
                const btn = document.getElementById("live-btn");

                if (isLive) {
                    statusLed.className = "w-2 h-2 rounded-full bg-emerald-400 animate-pulse";
                    statusText.innerText = "ONLINE";
                    statusText.className = "text-[9px] uppercase tracking-widest font-bold text-emerald-300 text-glow";
                    orbIcon.setAttribute('data-lucide', 'mic');
                    orb.className = "w-44 h-44 bg-zinc-900 border border-emerald-400/40 rounded-full orb-glow orb-listening flex items-center justify-center transition-all duration-300";
                    btn.innerHTML = '<i data-lucide="power"></i> ENCERRAR';
                    btn.className = "w-full py-6 bg-emerald-400 text-black rounded-3xl font-bold text-xs tracking-[0.3em] flex items-center justify-center gap-4 hover:bg-white transition-all shadow-xl";
                } else {
                    statusLed.className = "w-2 h-2 rounded-full bg-zinc-600";
                    statusText.innerText = "Standby";
                    statusText.className = "text-[9px] uppercase tracking-widest font-bold text-zinc-500";
                    orbIcon.setAttribute('data-lucide', 'mic-off');
                    orb.className = "w-44 h-44 bg-zinc-900 border border-white/10 rounded-full orb-glow flex items-center justify-center transition-all duration-300";
                    btn.innerHTML = '<i data-lucide="zap"></i> CONEXÃO LIVE';
                    btn.className = "w-full py-6 bg-white text-black rounded-3xl font-bold text-xs tracking-[0.3em] flex items-center justify-center gap-4 hover:bg-emerald-400 transition-all shadow-xl";
                }
                lucide.createIcons();
            };
        </script>
    </div>
</body>
</html>
