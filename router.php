<?php
declare(strict_types=1);

/**
 * Local router for PHP built-in server.
 * - Keeps default behavior for readable static files.
 * - Uses Git fallback when index/sala/agencia pages are unavailable locally.
 * - Exposes friendly routes:
 *   /sala-reuniao, /sala-reuniao.html, /agencia-3d, /agencia-3d.html
 * - Provides local API endpoints:
 *   /api/convocar-equipe, /api/agencia-chat, /api/start-admin-memoria
 */

$uri = parse_url($_SERVER['REQUEST_URI'] ?? '/', PHP_URL_PATH) ?: '/';
$docRoot = __DIR__;
$requested = $docRoot . str_replace('/', DIRECTORY_SEPARATOR, $uri);

require_once $docRoot . DIRECTORY_SEPARATOR . 'agencia-chat-lib.php';

/**
 * @return string|null
 */
function readLocalHtml(string $docRoot, string $relativePath): ?string
{
    $relativePath = ltrim(str_replace('\\', '/', $relativePath), '/');
    $fullPath = $docRoot . DIRECTORY_SEPARATOR . str_replace('/', DIRECTORY_SEPARATOR, $relativePath);
    if (!is_file($fullPath) || !is_readable($fullPath)) {
        return null;
    }

    $contents = file_get_contents($fullPath);
    return is_string($contents) ? $contents : null;
}

/**
 * @return string|null
 */
function readGitHtml(string $docRoot, string $relativePath): ?string
{
    $relativePath = ltrim(str_replace('\\', '/', $relativePath), '/');
    $cmd = 'git -C ' . escapeshellarg($docRoot) . ' show HEAD:' . $relativePath;
    $contents = shell_exec($cmd);
    return is_string($contents) ? $contents : null;
}

/**
 * @param string[] $candidatePaths
 * @return string|null
 */
function readHtmlWithFallback(string $docRoot, array $candidatePaths): ?string
{
    foreach ($candidatePaths as $path) {
        $local = readLocalHtml($docRoot, $path);
        if ($local !== null) {
            return $local;
        }
    }

    foreach ($candidatePaths as $path) {
        $fromGit = readGitHtml($docRoot, $path);
        if ($fromGit !== null) {
            return $fromGit;
        }
    }

    return null;
}

function renderHtml(string $html): bool
{
    header('Content-Type: text/html; charset=UTF-8');
    echo $html;
    return true;
}

function renderMissing(string $name): bool
{
    http_response_code(404);
    header('Content-Type: text/plain; charset=UTF-8');
    echo $name . ' unavailable (no local access and no Git fallback).';
    return true;
}

function renderJson(array $payload, int $statusCode = 200): bool
{
    http_response_code($statusCode);
    header('Content-Type: application/json; charset=UTF-8');
    echo json_encode($payload, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
    return true;
}

/**
 * @return string[]
 */
function getAllAgentNamesFromRegistry(string $docRoot): array
{
    $registryPath = $docRoot . DIRECTORY_SEPARATOR . 'memory-enterprise' . DIRECTORY_SEPARATOR
        . '60_AGENT_MEMORY' . DIRECTORY_SEPARATOR . 'runtime' . DIRECTORY_SEPARATOR . 'agents-registry.json';

    if (!is_file($registryPath) || !is_readable($registryPath)) {
        return [];
    }

    $raw = file_get_contents($registryPath);
    if (!is_string($raw) || trim($raw) === '') {
        return [];
    }

    $decoded = json_decode($raw, true);
    if (!is_array($decoded) || !isset($decoded['agents']) || !is_array($decoded['agents'])) {
        return [];
    }

    $names = [];
    foreach ($decoded['agents'] as $row) {
        if (!is_array($row)) {
            continue;
        }
        $name = trim((string)($row['name'] ?? ''));
        if ($name !== '') {
            $names[] = $name;
        }
    }

    $names = array_values(array_unique($names));
    sort($names, SORT_STRING | SORT_FLAG_CASE);
    return $names;
}

function runDetachedHeartbeat(string $docRoot, string $agentName, string $taskId, string $task, int $durationSec): bool
{
    $scriptPath = $docRoot . DIRECTORY_SEPARATOR . 'Agentes' . DIRECTORY_SEPARATOR . 'Gamificacao'
        . DIRECTORY_SEPARATOR . 'tests' . DIRECTORY_SEPARATOR . 'simulate-live-agent.ps1';

    if (!is_file($scriptPath)) {
        return false;
    }

    $duration = max(30, min(1800, $durationSec));
    $powershellCmd = 'powershell -NoProfile -ExecutionPolicy Bypass -File '
        . escapeshellarg($scriptPath)
        . ' -AgentName ' . escapeshellarg($agentName)
        . ' -TaskId ' . escapeshellarg($taskId)
        . ' -Task ' . escapeshellarg($task)
        . ' -DurationSec ' . (int)$duration;

    $cmd = 'cmd /c start "" /B ' . $powershellCmd;
    $proc = @popen($cmd, 'r');
    if (!is_resource($proc)) {
        return false;
    }
    @pclose($proc);
    return true;
}

function runDetachedAllAgentsHeartbeat(string $docRoot, int $durationSec, string $task): bool
{
    $scriptPath = $docRoot . DIRECTORY_SEPARATOR . 'Agentes' . DIRECTORY_SEPARATOR . 'Gamificacao'
        . DIRECTORY_SEPARATOR . 'tests' . DIRECTORY_SEPARATOR . 'simulate-live-all-agents.ps1';

    if (!is_file($scriptPath)) {
        return false;
    }

    $duration = max(30, min(1800, $durationSec));
    $powershellCmd = 'powershell -NoProfile -ExecutionPolicy Bypass -File '
        . escapeshellarg($scriptPath)
        . ' -DurationSec ' . (int)$duration
        . ' -Task ' . escapeshellarg($task);

    $cmd = 'cmd /c start "" /B ' . $powershellCmd;
    $proc = @popen($cmd, 'r');
    if (!is_resource($proc)) {
        return false;
    }
    @pclose($proc);
    return true;
}

function runDetachedAdminMemoria(string $docRoot): bool
{
    $scriptPath = $docRoot . DIRECTORY_SEPARATOR . 'run-admin-memoria-squad.ps1';
    if (!is_file($scriptPath)) {
        return false;
    }

    $powershellCmd = 'powershell -NoProfile -ExecutionPolicy Bypass -File '
        . escapeshellarg($scriptPath)
        . ' -NoOpenBrowser';
    $cmd = 'cmd /c start "" /B ' . $powershellCmd;

    $proc = @popen($cmd, 'r');
    if (!is_resource($proc)) {
        return false;
    }

    @pclose($proc);
    return true;
}

function injectIndexLinks(string $html): string
{
    $buttons = [];
    if (stripos($html, '/sala-reuniao') === false) {
        $buttons[] = '<a class="btn alt" href="/sala-reuniao.html">Sala de Reuniao</a>';
    }
    if (stripos($html, '/agencia-3d') === false) {
        $buttons[] = '<a class="btn alt" href="/agencia-3d.html">Agencia 3D</a>';
    }

    $bootScript = <<<'HTML'
<script>
(function(){
  function isAgencyLink(anchor){
    if(!anchor){return false;}
    var href=(anchor.getAttribute("href")||"").toLowerCase();
    return href.indexOf("/agencia-3d") !== -1;
  }
  function bootAndGo(anchor){
    var href=anchor.getAttribute("href")||"/agencia-3d.html";
    fetch("/api/start-admin-memoria",{
      method:"POST",
      headers:{"Content-Type":"application/json"},
      body:"{}",
      keepalive:true
    }).catch(function(){})
      .finally(function(){
        if(anchor.target && anchor.target !== "_self"){
          window.open(href, anchor.target);
          return;
        }
        window.location.href=href;
      });
  }
  document.addEventListener("click", function(evt){
    var anchor=evt.target && evt.target.closest ? evt.target.closest("a[href]") : null;
    if(!isAgencyLink(anchor)){return;}
    evt.preventDefault();
    bootAndGo(anchor);
  }, true);
})();
</script>
HTML;

    if (count($buttons) === 0) {
        if (stripos($html, '/api/start-admin-memoria') !== false) {
            return $html;
        }
        if (stripos($html, '</body>') !== false) {
            return str_ireplace('</body>', PHP_EOL . $bootScript . PHP_EOL . '</body>', $html);
        }
        return $html . PHP_EOL . $bootScript;
    }

    $buttonsHtml = implode(PHP_EOL . '                ', $buttons);
    $adminBtn = '<a class="btn alt" href="admin-memoria-squad.html">Painel Admin</a>';

    if (strpos($html, $adminBtn) !== false) {
        $updated = str_replace($adminBtn, $adminBtn . PHP_EOL . '                ' . $buttonsHtml, $html);
        if (stripos($updated, '/api/start-admin-memoria') !== false) {
            return $updated;
        }
        if (stripos($updated, '</body>') !== false) {
            return str_ireplace('</body>', PHP_EOL . $bootScript . PHP_EOL . '</body>', $updated);
        }
        return $updated . PHP_EOL . $bootScript;
    }

    $actionsBlock = '<div class="actions">';
    if (strpos($html, $actionsBlock) !== false) {
        $updated = str_replace($actionsBlock, $actionsBlock . PHP_EOL . '                ' . $buttonsHtml, $html);
        if (stripos($updated, '/api/start-admin-memoria') !== false) {
            return $updated;
        }
        if (stripos($updated, '</body>') !== false) {
            return str_ireplace('</body>', PHP_EOL . $bootScript . PHP_EOL . '</body>', $updated);
        }
        return $updated . PHP_EOL . $bootScript;
    }

    $fallbackLinks = '';
    $baseBottom = 18;
    foreach ($buttons as $idx => $buttonHtml) {
        $href = (strpos($buttonHtml, '/agencia-3d') !== false) ? '/agencia-3d.html' : '/sala-reuniao.html';
        $label = (strpos($buttonHtml, '/agencia-3d') !== false) ? 'Agencia 3D' : 'Sala de Reuniao';
        $bottom = $baseBottom + ($idx * 52);
        $fallbackLinks .= '<a href="' . $href . '" '
            . 'style="position:fixed;right:18px;bottom:' . $bottom . 'px;z-index:9999;padding:10px 14px;'
            . 'background:#2dd4bf;color:#032023;border-radius:10px;text-decoration:none;font-weight:700;'
            . 'box-shadow:0 8px 20px rgba(0,0,0,0.25)">' . $label . '</a>' . PHP_EOL;
    }

    if (stripos($html, '</body>') !== false) {
        return str_ireplace('</body>', PHP_EOL . $fallbackLinks . PHP_EOL . $bootScript . PHP_EOL . '</body>', $html);
    }

    return $html . PHP_EOL . $fallbackLinks . PHP_EOL . $bootScript;
}

if ($uri === '/api/convocar-equipe') {
    if (strtoupper($_SERVER['REQUEST_METHOD'] ?? 'GET') !== 'POST') {
        return renderJson(
            [
                'ok' => false,
                'error' => 'METHOD_NOT_ALLOWED',
            ],
            405
        );
    }

    $remoteAddr = (string)($_SERVER['REMOTE_ADDR'] ?? '');
    if (!in_array($remoteAddr, ['127.0.0.1', '::1'], true)) {
        return renderJson(
            [
                'ok' => false,
                'error' => 'LOCALHOST_ONLY',
            ],
            403
        );
    }

    $payload = [];
    $rawBody = file_get_contents('php://input');
    if (is_string($rawBody) && trim($rawBody) !== '') {
        $decoded = json_decode($rawBody, true);
        if (is_array($decoded)) {
            $payload = $decoded;
        }
    }

    $durationSec = 300;
    if (isset($payload['durationSec']) && is_numeric($payload['durationSec'])) {
        $durationSec = (int)$payload['durationSec'];
    }
    $durationSec = max(30, min(1800, $durationSec));

    $scope = strtolower(trim((string)($payload['scope'] ?? 'core')));
    if ($scope === '') {
        $scope = 'core';
    }

    $coreJobs = [
        [
            'agent' => 'Marcos',
            'task_id' => 'TASK-SALA-001',
            'task' => 'Criacao visual da Sala de Reuniao',
        ],
        [
            'agent' => 'Raquel',
            'task_id' => 'TASK-SALA-002',
            'task' => 'UX da Sala de Reuniao',
        ],
        [
            'agent' => 'Thiago',
            'task_id' => 'TASK-SALA-003',
            'task' => 'Validacao tecnica da Sala de Reuniao',
        ],
    ];

    $jobs = $coreJobs;
    if ($scope === 'all') {
        $agentNames = getAllAgentNamesFromRegistry($docRoot);
        if (count($agentNames) === 0) {
            return renderJson(
                [
                    'ok' => false,
                    'error' => 'REGISTRY_EMPTY',
                ],
                500
            );
        }

        $jobs = [];
        $idx = 1;
        foreach ($agentNames as $agentName) {
            $jobs[] = [
                'agent' => $agentName,
                'task_id' => 'TASK-SALA-ALL-' . str_pad((string)$idx, 3, '0', STR_PAD_LEFT),
                'task' => 'Mobilizacao geral da Sala de Reuniao',
            ];
            $idx++;
        }
    }

    $started = [];
    $failed = [];

    if ($scope === 'all') {
        $ok = runDetachedAllAgentsHeartbeat($docRoot, $durationSec, 'Mobilizacao geral da Sala de Reuniao');
        if ($ok) {
            $started = $jobs;
        } else {
            $failed = $jobs;
        }
    } else {
        foreach ($jobs as $job) {
            $ok = runDetachedHeartbeat(
                $docRoot,
                (string)$job['agent'],
                (string)$job['task_id'],
                (string)$job['task'],
                $durationSec
            );
            if ($ok) {
                $started[] = $job;
            } else {
                $failed[] = $job;
            }
        }
    }

    $statusCode = count($failed) > 0 ? 500 : 200;
    return renderJson(
        [
            'ok' => count($failed) === 0,
            'scope' => $scope,
            'duration_sec' => $durationSec,
            'requested' => count($jobs),
            'started' => $started,
            'failed' => $failed,
            'monitor_url' => 'http://127.0.0.1:8095/admin-memoria-squad.html',
        ],
        $statusCode
    );
}

if ($uri === '/api/agencia-chat') {
    return agency_handle_chat_api($docRoot);
}

if ($uri === '/api/start-admin-memoria') {
    if (strtoupper($_SERVER['REQUEST_METHOD'] ?? 'GET') !== 'POST') {
        return renderJson(
            [
                'ok' => false,
                'error' => 'METHOD_NOT_ALLOWED',
            ],
            405
        );
    }

    $remoteAddr = (string)($_SERVER['REMOTE_ADDR'] ?? '');
    if (!in_array($remoteAddr, ['127.0.0.1', '::1'], true)) {
        return renderJson(
            [
                'ok' => false,
                'error' => 'LOCALHOST_ONLY',
            ],
            403
        );
    }

    $ok = runDetachedAdminMemoria($docRoot);
    if (!$ok) {
        return renderJson(
            [
                'ok' => false,
                'error' => 'SCRIPT_START_FAILED',
                'script' => 'run-admin-memoria-squad.ps1',
            ],
            500
        );
    }

    return renderJson(
        [
            'ok' => true,
            'message' => 'run-admin-memoria-squad.ps1 disparado.',
            'monitor_url' => 'http://127.0.0.1:8095/admin-memoria-squad.html',
        ]
    );
}

if ($uri === '/' || $uri === '/index' || $uri === '/index.html') {
    $indexHtml = readHtmlWithFallback($docRoot, ['index.html']);
    if ($indexHtml === null) {
        return renderMissing('index.html');
    }

    return renderHtml(injectIndexLinks($indexHtml));
}

if ($uri === '/sala-reuniao' || $uri === '/sala-reuniao.html') {
    $meetingHtml = readHtmlWithFallback(
        $docRoot,
        [
            'sala-reuniao.html',
            'Agentes/sala-reuniao.html',
            'Agentes/Sala-Reuniao/sala-reuniao.html',
        ]
    );

    if ($meetingHtml === null) {
        return renderMissing('sala-reuniao.html');
    }

    return renderHtml($meetingHtml);
}

if ($uri === '/agencia-3d' || $uri === '/agencia-3d.html') {
    $agencyHtml = readHtmlWithFallback(
        $docRoot,
        [
            'agencia-3d.html',
            'Agentes/agencia-3d.html',
            'Agentes/Sala-Reuniao/agencia-3d.html',
        ]
    );

    if ($agencyHtml === null) {
        return renderMissing('agencia-3d.html');
    }

    return renderHtml($agencyHtml);
}

if (is_file($requested) && is_readable($requested)) {
    return false;
}

return false;
