<?php
declare(strict_types=1);

/**
 * Agencia 3D chat orchestrator (local PHP server).
 * - Routes @nomedoagente / @todos
 * - Loads personality/context from memory-enterprise
 * - Persists user/session memory
 * - Emits detailed orchestration events for admin-memoria-squad.html
 */

function agency_now_iso(): string
{
    return gmdate('Y-m-d\TH:i:s\Z');
}

function agency_text_lower(string $value): string
{
    if (function_exists('mb_strtolower')) {
        return (string)mb_strtolower($value);
    }
    return strtolower($value);
}

function agency_text_contains(string $haystack, string $needle): bool
{
    if (function_exists('mb_stripos')) {
        return mb_stripos($haystack, $needle) !== false;
    }
    return stripos($haystack, $needle) !== false;
}

function agency_text_length(string $value): int
{
    if (function_exists('mb_strlen')) {
        return (int)mb_strlen($value);
    }
    return strlen($value);
}

function agency_text_substr(string $value, int $start, int $length): string
{
    if (function_exists('mb_substr')) {
        return (string)mb_substr($value, $start, $length);
    }
    return substr($value, $start, $length);
}

function agency_runtime_file(string $docRoot, string $fileName): string
{
    return $docRoot . DIRECTORY_SEPARATOR
        . 'memory-enterprise' . DIRECTORY_SEPARATOR
        . '60_AGENT_MEMORY' . DIRECTORY_SEPARATOR
        . 'runtime' . DIRECTORY_SEPARATOR
        . $fileName;
}

function agency_ensure_parent_dir(string $path): void
{
    $dir = dirname($path);
    if (!is_dir($dir)) {
        @mkdir($dir, 0777, true);
    }
}

function agency_read_json_file(string $path, array $defaultValue): array
{
    if (!is_file($path) || !is_readable($path)) {
        return $defaultValue;
    }
    $raw = @file_get_contents($path);
    if (!is_string($raw) || trim($raw) === '') {
        return $defaultValue;
    }
    $decoded = json_decode($raw, true);
    return is_array($decoded) ? $decoded : $defaultValue;
}

function agency_write_json_file(string $path, array $payload): bool
{
    agency_ensure_parent_dir($path);
    $json = json_encode($payload, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES | JSON_PRETTY_PRINT);
    if (!is_string($json)) {
        return false;
    }
    return @file_put_contents($path, $json . PHP_EOL, LOCK_EX) !== false;
}

function agency_env(string $name, string $default = ''): string
{
    $value = getenv($name);
    if ($value === false) {
        return $default;
    }
    $text = trim((string)$value);
    return $text === '' ? $default : $text;
}

/**
 * @param string[] $headers
 * @return array{ok: bool, status: int, body: string, error: string}
 */
function agency_http_post_json(string $url, array $headers, array $payload, int $timeoutSec = 25): array
{
    $json = json_encode($payload, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
    if (!is_string($json)) {
        return [
            'ok' => false,
            'status' => 0,
            'body' => '',
            'error' => 'JSON_ENCODE_FAILED',
        ];
    }

    $allHeaders = array_merge(['Content-Type: application/json'], $headers);
    $context = stream_context_create(
        [
            'http' => [
                'method' => 'POST',
                'header' => implode("\r\n", $allHeaders),
                'content' => $json,
                'ignore_errors' => true,
                'timeout' => $timeoutSec,
            ],
        ]
    );

    $body = @file_get_contents($url, false, $context);
    $status = 0;
    $responseHeaders = $http_response_header ?? [];
    if (is_array($responseHeaders)) {
        foreach ($responseHeaders as $line) {
            if (preg_match('#^HTTP/\S+\s+(\d{3})#', (string)$line, $m) === 1) {
                $status = (int)$m[1];
                break;
            }
        }
    }

    if (!is_string($body)) {
        $body = '';
    }

    return [
        'ok' => $status >= 200 && $status < 300,
        'status' => $status,
        'body' => $body,
        'error' => ($status >= 200 && $status < 300) ? '' : ('HTTP_' . $status),
    ];
}

function agency_normalize_gemini_model(string $raw): string
{
    $model = trim($raw);
    if (substr($model, 0, 7) === 'models/') {
        $model = substr($model, 7);
    }
    return $model !== '' ? $model : 'gemini-2.0-flash';
}

/**
 * @return array{enabled: bool, provider: string, model: string, api_key: string}
 */
function agency_model_config(): array
{
    $provider = agency_text_lower(agency_env('AGENCIA_CHAT_PROVIDER', 'auto'));
    $openaiKey = agency_env('OPENAI_API_KEY');
    $geminiKey = agency_env('GEMINI_API_KEY', agency_env('GOOGLE_API_KEY'));

    $openaiModel = agency_env('AGENCIA_CHAT_OPENAI_MODEL', agency_env('OPENAI_MODEL', 'gpt-4o-mini'));
    $geminiModel = agency_normalize_gemini_model(
        agency_env('AGENCIA_CHAT_GEMINI_MODEL', agency_env('GEMINI_TEXT_MODEL_ID', 'gemini-2.0-flash'))
    );

    if ($provider === 'openai' && $openaiKey !== '') {
        return ['enabled' => true, 'provider' => 'openai', 'model' => $openaiModel, 'api_key' => $openaiKey];
    }
    if ($provider === 'gemini' && $geminiKey !== '') {
        return ['enabled' => true, 'provider' => 'gemini', 'model' => $geminiModel, 'api_key' => $geminiKey];
    }
    if ($provider === 'auto') {
        if ($openaiKey !== '') {
            return ['enabled' => true, 'provider' => 'openai', 'model' => $openaiModel, 'api_key' => $openaiKey];
        }
        if ($geminiKey !== '') {
            return ['enabled' => true, 'provider' => 'gemini', 'model' => $geminiModel, 'api_key' => $geminiKey];
        }
    }

    return ['enabled' => false, 'provider' => 'none', 'model' => '', 'api_key' => ''];
}

function agency_compact_text(string $text, int $maxLen = 280): string
{
    $clean = trim(preg_replace('/\s+/u', ' ', $text) ?? $text);
    if ($clean === '') {
        return '';
    }
    if (agency_text_length($clean) <= $maxLen) {
        return $clean;
    }
    return rtrim(agency_text_substr($clean, 0, $maxLen - 1)) . '…';
}

function agency_recent_history_text(array $session, int $limit = 8): string
{
    $messages = isset($session['messages']) && is_array($session['messages']) ? $session['messages'] : [];
    if (count($messages) === 0) {
        return '';
    }

    $slice = array_slice($messages, -$limit);
    $lines = [];
    foreach ($slice as $row) {
        if (!is_array($row)) {
            continue;
        }
        $speaker = trim((string)($row['speaker'] ?? ($row['role'] ?? 'alguem')));
        $text = agency_compact_text((string)($row['text'] ?? ''), 240);
        if ($text === '') {
            continue;
        }
        $lines[] = $speaker . ': ' . $text;
    }
    return implode("\n", $lines);
}

function agency_model_system_prompt(
    array $agent,
    array $context,
    array $topicDepartments,
    bool $responsibilityQuestion,
    string $preferredName,
    bool $isLeader
): string {
    $name = (string)($agent['name'] ?? 'Agente');
    $role = trim((string)($context['role'] ?? 'especialista'));
    $dept = agency_department_for_agent($agent);
    $deptLabel = agency_department_label($dept);
    $topic = agency_topic_label($topicDepartments);
    $ownedAreas = isset($context['owned_areas']) && is_array($context['owned_areas']) ? $context['owned_areas'] : [];
    $shortContext = isset($context['short_context']) && is_array($context['short_context']) ? $context['short_context'] : [];
    $nextActions = isset($context['next_actions']) && is_array($context['next_actions']) ? $context['next_actions'] : [];

    $owned = count($ownedAreas) > 0 ? implode(', ', array_slice($ownedAreas, 0, 5)) : 'sem areas detalhadas';
    $ctx = count($shortContext) > 0 ? implode(' | ', array_slice($shortContext, 0, 3)) : 'sem contexto recente';
    $actions = count($nextActions) > 0 ? implode(' | ', array_slice($nextActions, 0, 3)) : 'sem proximas acoes registradas';
    $currentTask = trim((string)($context['current_task'] ?? ''));
    $status = trim((string)($context['status'] ?? ''));
    $userName = $preferredName !== '' ? $preferredName : 'CEO';

    return trim(
        "Voce e {$name}, {$role}, do departamento {$deptLabel}.\n" .
        "Fale sempre em portugues do Brasil, em primeira pessoa, com objetividade e clareza.\n" .
        "Tema da conversa: {$topic}.\n" .
        "Usuario atual: {$userName}.\n" .
        "Contexto do agente:\n" .
        "- Areas: {$owned}\n" .
        "- Status: " . ($status !== '' ? $status : 'nao informado') . "\n" .
        "- Tarefa atual: " . ($currentTask !== '' ? $currentTask : 'nao informada') . "\n" .
        "- Contexto curto: {$ctx}\n" .
        "- Proximas acoes: {$actions}\n" .
        "- Lider do assunto: " . ($isLeader ? 'sim' : 'nao') . "\n" .
        "- Pergunta de responsabilidade: " . ($responsibilityQuestion ? 'sim' : 'nao') . "\n" .
        "Regras:\n" .
        "1) Responda entre 2 e 5 frases.\n" .
        "2) Se for pergunta de responsabilidade, diga quem lidera e quem executa.\n" .
        "3) Se faltar dado, diga o que vai validar agora.\n" .
        "4) Nao invente numeros nem fatos internos sem base no contexto.\n" .
        "5) Evite texto genérico e evite repetir exatamente o mesmo padrão em toda resposta."
    );
}

function agency_model_user_prompt(string $message, array $session): string
{
    $history = agency_recent_history_text($session, 8);
    if ($history === '') {
        return "Mensagem do usuario:\n{$message}";
    }
    return "Historico recente:\n{$history}\n\nMensagem atual do usuario:\n{$message}";
}

/**
 * @return array{ok: bool, text: string, error: string}
 */
function agency_generate_with_openai(string $apiKey, string $model, string $systemPrompt, string $userPrompt): array
{
    $response = agency_http_post_json(
        'https://api.openai.com/v1/chat/completions',
        ['Authorization: Bearer ' . $apiKey],
        [
            'model' => $model,
            'messages' => [
                ['role' => 'system', 'content' => $systemPrompt],
                ['role' => 'user', 'content' => $userPrompt],
            ],
            'temperature' => 0.6,
            'max_tokens' => 260,
        ],
        28
    );

    if (!$response['ok']) {
        return ['ok' => false, 'text' => '', 'error' => 'OPENAI_' . $response['error']];
    }

    $decoded = json_decode($response['body'], true);
    if (!is_array($decoded)) {
        return ['ok' => false, 'text' => '', 'error' => 'OPENAI_INVALID_JSON'];
    }

    $content = $decoded['choices'][0]['message']['content'] ?? '';
    $text = '';
    if (is_string($content)) {
        $text = trim($content);
    } elseif (is_array($content)) {
        $parts = [];
        foreach ($content as $piece) {
            if (is_array($piece) && isset($piece['text']) && is_string($piece['text'])) {
                $parts[] = $piece['text'];
            }
        }
        $text = trim(implode("\n", $parts));
    }

    if ($text === '') {
        return ['ok' => false, 'text' => '', 'error' => 'OPENAI_EMPTY_TEXT'];
    }

    return ['ok' => true, 'text' => $text, 'error' => ''];
}

/**
 * @return array{ok: bool, text: string, error: string}
 */
function agency_generate_with_gemini(string $apiKey, string $model, string $systemPrompt, string $userPrompt): array
{
    $url = 'https://generativelanguage.googleapis.com/v1beta/models/'
        . rawurlencode($model)
        . ':generateContent?key='
        . rawurlencode($apiKey);

    $response = agency_http_post_json(
        $url,
        [],
        [
            'systemInstruction' => [
                'parts' => [
                    ['text' => $systemPrompt],
                ],
            ],
            'contents' => [
                [
                    'role' => 'user',
                    'parts' => [
                        ['text' => $userPrompt],
                    ],
                ],
            ],
            'generationConfig' => [
                'temperature' => 0.6,
                'maxOutputTokens' => 260,
            ],
        ],
        28
    );

    if (!$response['ok']) {
        return ['ok' => false, 'text' => '', 'error' => 'GEMINI_' . $response['error']];
    }

    $decoded = json_decode($response['body'], true);
    if (!is_array($decoded)) {
        return ['ok' => false, 'text' => '', 'error' => 'GEMINI_INVALID_JSON'];
    }

    $parts = $decoded['candidates'][0]['content']['parts'] ?? [];
    $texts = [];
    if (is_array($parts)) {
        foreach ($parts as $part) {
            if (is_array($part) && isset($part['text']) && is_string($part['text'])) {
                $texts[] = $part['text'];
            }
        }
    }
    $text = trim(implode("\n", $texts));
    if ($text === '') {
        return ['ok' => false, 'text' => '', 'error' => 'GEMINI_EMPTY_TEXT'];
    }

    return ['ok' => true, 'text' => $text, 'error' => ''];
}

/**
 * @param array<string, mixed> $modelConfig
 * @param array<string, mixed> $agent
 * @param array<string, mixed> $context
 * @param array<string, mixed> $session
 * @return array{ok: bool, text: string, provider: string, model: string, error: string}
 */
function agency_generate_agent_reply_with_model(
    array $modelConfig,
    array $agent,
    array $context,
    string $message,
    array $topicDepartments,
    bool $responsibilityQuestion,
    string $preferredName,
    bool $isLeader,
    array $session
): array {
    $enabled = (bool)($modelConfig['enabled'] ?? false);
    $provider = (string)($modelConfig['provider'] ?? 'none');
    $model = (string)($modelConfig['model'] ?? '');
    $apiKey = (string)($modelConfig['api_key'] ?? '');

    if (!$enabled || $provider === 'none' || $model === '' || $apiKey === '') {
        return ['ok' => false, 'text' => '', 'provider' => $provider, 'model' => $model, 'error' => 'MODEL_DISABLED'];
    }

    $systemPrompt = agency_model_system_prompt(
        $agent,
        $context,
        $topicDepartments,
        $responsibilityQuestion,
        $preferredName,
        $isLeader
    );
    $userPrompt = agency_model_user_prompt($message, $session);

    if ($provider === 'openai') {
        $result = agency_generate_with_openai($apiKey, $model, $systemPrompt, $userPrompt);
    } elseif ($provider === 'gemini') {
        $result = agency_generate_with_gemini($apiKey, $model, $systemPrompt, $userPrompt);
    } else {
        return ['ok' => false, 'text' => '', 'provider' => $provider, 'model' => $model, 'error' => 'UNKNOWN_PROVIDER'];
    }

    if (!(bool)$result['ok']) {
        return [
            'ok' => false,
            'text' => '',
            'provider' => $provider,
            'model' => $model,
            'error' => (string)($result['error'] ?? 'MODEL_ERROR'),
        ];
    }

    $text = agency_compact_text((string)$result['text'], 750);
    if ($text === '') {
        return ['ok' => false, 'text' => '', 'provider' => $provider, 'model' => $model, 'error' => 'EMPTY_OUTPUT'];
    }

    return ['ok' => true, 'text' => $text, 'provider' => $provider, 'model' => $model, 'error' => ''];
}

/**
 * @param array<string, mixed> $meta
 */
function agency_append_event(
    string $docRoot,
    string $kind,
    string $level,
    string $message,
    array $meta = []
): array {
    $path = agency_runtime_file($docRoot, 'agencia-chat-events.json');
    $data = agency_read_json_file(
        $path,
        [
            'generated_at' => agency_now_iso(),
            'next_seq' => 1,
            'events' => [],
        ]
    );

    $seq = (int)($data['next_seq'] ?? 1);
    if ($seq < 1) {
        $seq = 1;
    }

    $event = [
        'seq' => $seq,
        'at' => agency_now_iso(),
        'kind' => $kind,
        'level' => $level,
        'message' => $message,
        'meta' => $meta,
    ];

    $events = [];
    if (isset($data['events']) && is_array($data['events'])) {
        $events = $data['events'];
    }
    $events[] = $event;
    if (count($events) > 1500) {
        $events = array_slice($events, -1500);
    }

    $data['events'] = array_values($events);
    $data['next_seq'] = $seq + 1;
    $data['generated_at'] = agency_now_iso();
    agency_write_json_file($path, $data);

    return $event;
}

function agency_slug(string $value): string
{
    $raw = trim($value);
    if ($raw === '') {
        return '';
    }

    $ascii = @iconv('UTF-8', 'ASCII//TRANSLIT//IGNORE', $raw);
    $base = is_string($ascii) && $ascii !== '' ? $ascii : $raw;
    $base = strtolower($base);
    $base = preg_replace('/[^a-z0-9]+/', '-', $base) ?? '';
    $base = trim($base, '-');
    return $base;
}

/**
 * @return array{users: array<string, mixed>, sessions: array<string, mixed>, generated_at: string}
 */
function agency_load_memory(string $docRoot): array
{
    $path = agency_runtime_file($docRoot, 'agencia-chat-memory.json');
    $data = agency_read_json_file(
        $path,
        [
            'generated_at' => agency_now_iso(),
            'users' => [],
            'sessions' => [],
        ]
    );

    if (!isset($data['users']) || !is_array($data['users'])) {
        $data['users'] = [];
    }
    if (!isset($data['sessions']) || !is_array($data['sessions'])) {
        $data['sessions'] = [];
    }
    if (!isset($data['generated_at']) || !is_string($data['generated_at'])) {
        $data['generated_at'] = agency_now_iso();
    }

    return $data;
}

function agency_save_memory(string $docRoot, array $memory): bool
{
    $memory['generated_at'] = agency_now_iso();
    $path = agency_runtime_file($docRoot, 'agencia-chat-memory.json');
    return agency_write_json_file($path, $memory);
}

function agency_detect_preferred_name_command(string $text): ?string
{
    $patterns = [
        '/\b(?:me\s+chame|me\s+chamar|quero\s+que\s+me\s+chame|pode\s+me\s+chamar)\s+de\s+(.+)$/iu',
        '/\bmeu\s+nome\s+(?:e|é)\s+(.+)$/iu',
    ];

    foreach ($patterns as $pattern) {
        if (preg_match($pattern, trim($text), $m) !== 1) {
            continue;
        }
        $name = trim((string)($m[1] ?? ''));
        $name = preg_split('/[,.;!?]/u', $name, 2)[0] ?? $name;
        $name = trim($name, " \t\n\r\0\x0B\"'`´");
        if ($name === '') {
            return null;
        }
        if (agency_text_length($name) > 60) {
            $name = agency_text_substr($name, 0, 60);
        }
        return $name;
    }

    return null;
}

function agency_yaml_scalar(string $text, string $key): string
{
    $pattern = '/^\s*' . preg_quote($key, '/') . '\s*:\s*(.+?)\s*$/mi';
    if (preg_match($pattern, $text, $m) !== 1) {
        return '';
    }
    $value = trim((string)$m[1]);
    return trim($value, "\"'");
}

/**
 * @return string[]
 */
function agency_yaml_list(string $text, string $key): array
{
    $lines = preg_split('/\r?\n/', $text) ?: [];
    $out = [];
    $on = false;
    foreach ($lines as $line) {
        $trim = trim($line);
        if ($trim === '') {
            continue;
        }
        if (!$on && strcasecmp($trim, $key . ':') === 0) {
            $on = true;
            continue;
        }
        if (!$on) {
            continue;
        }
        if (preg_match('/^[A-Za-z0-9_]+:/', $trim) === 1) {
            break;
        }
        if (preg_match('/^\s*-\s+(.+)$/', $line, $m) === 1) {
            $item = trim((string)$m[1], " \t\n\r\0\x0B\"'");
            if ($item !== '') {
                $out[] = $item;
            }
        }
    }
    return $out;
}

/**
 * @return array<int, array{name:string,slug:string,specialty:string,working_set:string,profile:string}>
 */
function agency_load_registry_agents(string $docRoot): array
{
    $path = agency_runtime_file($docRoot, 'agents-registry.json');
    $data = agency_read_json_file($path, ['agents' => []]);
    $rows = isset($data['agents']) && is_array($data['agents']) ? $data['agents'] : [];

    $out = [];
    foreach ($rows as $row) {
        if (!is_array($row)) {
            continue;
        }
        $name = trim((string)($row['name'] ?? ''));
        $slug = trim((string)($row['slug'] ?? ''));
        if ($name === '' && $slug === '') {
            continue;
        }
        if ($name === '') {
            $name = $slug;
        }
        if ($slug === '') {
            $slug = agency_slug($name);
        }
        $out[] = [
            'name' => $name,
            'slug' => $slug,
            'specialty' => trim((string)($row['specialty'] ?? '')),
            'working_set' => trim((string)($row['working_set'] ?? '')),
            'profile' => trim((string)($row['profile'] ?? '')),
        ];
    }

    usort(
        $out,
        static fn(array $a, array $b): int => strcasecmp($a['name'], $b['name'])
    );

    return $out;
}

function agency_department_for_agent(array $agent): string
{
    $txt = strtolower(($agent['name'] ?? '') . ' ' . ($agent['specialty'] ?? ''));
    if (preg_match('/jarvina|locutora|voz|audio|musical|trilha|narr/', $txt) === 1) {
        return 'voz';
    }
    if (preg_match('/regional|comercial|vendas|cliente/', $txt) === 1) {
        return 'comercial';
    }
    if (preg_match('/marketing|social|seo|influencer|performance|growth/', $txt) === 1) {
        return 'marketing';
    }
    if (preg_match('/designer|design|motion|ux|criativ/', $txt) === 1) {
        return 'design';
    }
    if (preg_match('/qa|developer|infra|ai|full-stack|validation|tech|backend|front-end/', $txt) === 1) {
        return 'tech';
    }
    return 'direcao';
}

function agency_department_label(string $dept): string
{
    return match ($dept) {
        'tech' => 'Produto e Tecnologia',
        'design' => 'Design e Criacao',
        'marketing' => 'Marketing e Midia',
        'comercial' => 'Comercial Regional',
        'voz' => 'Voz e Conteudo',
        default => 'Direcao e Operacoes',
    };
}

/**
 * @return array<string, string[]>
 */
function agency_topic_keywords(): array
{
    return [
        'tech' => ['deploy', 'backend', 'api', 'infra', 'bug', 'erro', 'falha', 'qa', 'teste', 'codigo', 'sistema', 'railway', 'websocket', 'ws'],
        'design' => ['design', 'ux', 'ui', 'layout', 'identidade', 'criativo', 'criacao', 'motion', 'visual', 'arte'],
        'marketing' => ['campanha', 'trafego', 'seo', 'social', 'midia', 'ads', 'influencer', 'marketing', 'performance'],
        'comercial' => ['cliente', 'comercial', 'regional', 'vendas', 'contrato', 'expansao', 'negocio'],
        'voz' => ['voz', 'audio', 'locucao', 'narracao', 'trilha', 'musica', 'jarvina'],
        'direcao' => ['estrategia', 'prioridade', 'roadmap', 'pmo', 'governanca', 'lideranca', 'ceo', 'sanntiago'],
    ];
}

/**
 * @return string[]
 */
function agency_detect_topic_departments(string $message): array
{
    $msg = agency_text_lower($message);
    $found = [];
    foreach (agency_topic_keywords() as $dept => $keys) {
        foreach ($keys as $key) {
            if (agency_text_contains($msg, $key)) {
                $found[$dept] = true;
                break;
            }
        }
    }
    return array_keys($found);
}

function agency_is_responsibility_question(string $message): bool
{
    $msg = agency_text_lower($message);
    if (!agency_text_contains($msg, 'quem')) {
        return false;
    }
    return agency_text_contains($msg, 'respons')
        || agency_text_contains($msg, 'cuida')
        || agency_text_contains($msg, 'lider');
}

/**
 * @return array<string, mixed>
 */
function agency_load_agent_context(string $docRoot, array $agent): array
{
    $profileText = '';
    $workingText = '';

    $profilePath = trim((string)($agent['profile'] ?? ''));
    if ($profilePath !== '') {
        $full = $docRoot . DIRECTORY_SEPARATOR . str_replace('/', DIRECTORY_SEPARATOR, $profilePath);
        if (is_file($full) && is_readable($full)) {
            $raw = file_get_contents($full);
            $profileText = is_string($raw) ? $raw : '';
        }
    }

    $workingPath = trim((string)($agent['working_set'] ?? ''));
    if ($workingPath !== '') {
        $full = $docRoot . DIRECTORY_SEPARATOR . str_replace('/', DIRECTORY_SEPARATOR, $workingPath);
        if (is_file($full) && is_readable($full)) {
            $raw = file_get_contents($full);
            $workingText = is_string($raw) ? $raw : '';
        }
    }

    $role = agency_yaml_scalar($profileText, 'role');
    if ($role === '') {
        $role = trim((string)($agent['specialty'] ?? ''));
    }
    if ($role === '') {
        $role = 'especialista do squad';
    }

    $ownedAreas = agency_yaml_list($profileText, 'owned_areas');
    $knownConstraints = agency_yaml_list($profileText, 'known_constraints');
    $status = agency_yaml_scalar($workingText, 'status');
    $currentTask = agency_yaml_scalar($workingText, 'current_task');
    $shortContext = agency_yaml_list($workingText, 'short_term_context');
    $nextActions = agency_yaml_list($workingText, 'next_3_actions');

    return [
        'role' => $role,
        'owned_areas' => $ownedAreas,
        'known_constraints' => $knownConstraints,
        'status' => $status,
        'current_task' => $currentTask,
        'short_context' => $shortContext,
        'next_actions' => $nextActions,
    ];
}

/**
 * @return string[]
 */
function agency_parse_mentions(string $message): array
{
    if (preg_match_all('/@([A-Za-z0-9_-]+)/', $message, $m) !== 1) {
        return [];
    }
    $tokens = $m[1] ?? [];
    $mentions = [];
    foreach ($tokens as $token) {
        $slug = agency_slug((string)$token);
        if ($slug !== '') {
            $mentions[] = $slug;
        }
    }
    return array_values(array_unique($mentions));
}

/**
 * @param array<int, array{name:string,slug:string,specialty:string,working_set:string,profile:string}> $agents
 * @return array<int, array{name:string,slug:string,specialty:string,working_set:string,profile:string}>
 */
function agency_resolve_mentions(array $agents, array $mentions): array
{
    $index = [];
    foreach ($agents as $agent) {
        $index[(string)$agent['slug']] = $agent;
        $index[agency_slug((string)$agent['name'])] = $agent;
    }

    $resolved = [];
    foreach ($mentions as $mention) {
        if (!isset($index[$mention])) {
            continue;
        }
        $resolved[(string)$index[$mention]['slug']] = $index[$mention];
    }
    return array_values($resolved);
}

/**
 * @param array<int, array{name:string,slug:string,specialty:string,working_set:string,profile:string}> $agents
 * @return array<string, array{name:string,slug:string,specialty:string,working_set:string,profile:string}>
 */
function agency_build_department_leaders(array $agents): array
{
    $byDept = [];
    foreach ($agents as $agent) {
        $dept = agency_department_for_agent($agent);
        if (!isset($byDept[$dept])) {
            $byDept[$dept] = [];
        }
        $byDept[$dept][] = $agent;
    }

    $candidates = [
        'tech' => ['marcos', 'ricardo', 'igor'],
        'design' => ['raquel', 'bruno', 'julia'],
        'marketing' => ['amanda', 'lucas', 'vinicius'],
        'comercial' => ['roberto', 'patricia', 'sandra', 'luiz'],
        'voz' => ['jarvina', 'sofia', 'carlos', 'pedro'],
        'direcao' => ['assistant', 'helena', 'renata'],
    ];

    $leaders = [];
    foreach ($byDept as $dept => $members) {
        $chosen = null;
        foreach (($candidates[$dept] ?? []) as $candSlug) {
            foreach ($members as $member) {
                if (agency_slug((string)$member['slug']) === $candSlug || agency_slug((string)$member['name']) === $candSlug) {
                    $chosen = $member;
                    break 2;
                }
            }
        }
        if ($chosen === null && count($members) > 0) {
            $chosen = $members[0];
        }
        if ($chosen !== null) {
            $leaders[$dept] = $chosen;
        }
    }

    return $leaders;
}

/**
 * @param array<int, array{name:string,slug:string,specialty:string,working_set:string,profile:string}> $agents
 * @return array{mention_all: bool, mentions: string[], topic_departments: string[], responsibility_question: bool, responders: array<int, array{name:string,slug:string,specialty:string,working_set:string,profile:string}>}
 */
function agency_select_responders(array $agents, string $message): array
{
    $mentions = agency_parse_mentions($message);
    $mentionAll = in_array('todos', $mentions, true) || in_array('all', $mentions, true);
    $topicDepartments = agency_detect_topic_departments($message);
    $responsibilityQuestion = agency_is_responsibility_question($message);
    $leaders = agency_build_department_leaders($agents);

    $responders = [];
    $explicit = agency_resolve_mentions($agents, $mentions);
    if (!$mentionAll && count($explicit) > 0) {
        $responders = $explicit;
    } elseif ($responsibilityQuestion) {
        $wantedDepts = count($topicDepartments) > 0 ? $topicDepartments : array_keys($leaders);
        foreach ($wantedDepts as $dept) {
            if (isset($leaders[$dept])) {
                $responders[] = $leaders[$dept];
            }
        }
    } elseif ($mentionAll) {
        $wanted = count($topicDepartments) > 0 ? array_flip($topicDepartments) : [];
        if (count($wanted) > 0) {
            foreach ($agents as $agent) {
                $dept = agency_department_for_agent($agent);
                if (isset($wanted[$dept])) {
                    $responders[] = $agent;
                }
            }
        } else {
            foreach ($leaders as $leader) {
                $responders[] = $leader;
            }
        }
    } else {
        foreach ($leaders as $leader) {
            $responders[] = $leader;
        }
        // Prefer Jarvina as first fallback speaker.
        $jarvina = agency_resolve_mentions($agents, ['jarvina']);
        if (count($jarvina) > 0) {
            array_unshift($responders, $jarvina[0]);
        }
    }

    $uniq = [];
    foreach ($responders as $responder) {
        $uniq[(string)$responder['slug']] = $responder;
    }
    $responders = array_values($uniq);

    if (count($responders) === 0 && count($agents) > 0) {
        $responders = [$agents[0]];
    }

    return [
        'mention_all' => $mentionAll,
        'mentions' => $mentions,
        'topic_departments' => $topicDepartments,
        'responsibility_question' => $responsibilityQuestion,
        'responders' => $responders,
    ];
}

function agency_topic_label(array $topicDepartments): string
{
    if (count($topicDepartments) === 0) {
        return 'escopo geral da agência';
    }
    $labels = [];
    foreach ($topicDepartments as $dept) {
        $labels[] = agency_department_label((string)$dept);
    }
    return implode(' + ', $labels);
}

/**
 * @param array<string, mixed> $agent
 * @param array<string, mixed> $context
 */
function agency_build_agent_reply(
    array $agent,
    array $context,
    string $message,
    array $topicDepartments,
    bool $responsibilityQuestion,
    string $preferredName,
    bool $isLeader
): string {
    $name = (string)($agent['name'] ?? 'Agente');
    $role = trim((string)($context['role'] ?? 'especialista'));
    $dept = agency_department_for_agent($agent);
    $deptLabel = agency_department_label($dept);
    $topic = agency_topic_label($topicDepartments);
    $prefix = $preferredName !== '' ? $preferredName . ', ' : '';

    $ownedAreas = isset($context['owned_areas']) && is_array($context['owned_areas']) ? $context['owned_areas'] : [];
    $ownedText = count($ownedAreas) > 0 ? implode(', ', array_slice($ownedAreas, 0, 3)) : $deptLabel;
    $currentTask = trim((string)($context['current_task'] ?? ''));
    $shortContext = isset($context['short_context']) && is_array($context['short_context']) ? $context['short_context'] : [];
    $hint = count($shortContext) > 0 ? (string)$shortContext[0] : '';

    if ($responsibilityQuestion) {
        if ($isLeader) {
            return $prefix . "sou {$name}, líder de {$deptLabel}. Para \"{$topic}\" eu assumo a responsabilidade e aciono o time agora.";
        }
        return $prefix . "sou {$name} ({$role}). Para \"{$topic}\", o ponto focal é a liderança de {$deptLabel}.";
    }

    $reply = $prefix . "sou {$name} ({$role}). Na frente de {$deptLabel}, atuo em {$ownedText}.";
    if ($currentTask !== '') {
        $reply .= " Tarefa atual: {$currentTask}.";
    }
    if ($hint !== '') {
        $reply .= " Contexto rápido: {$hint}.";
    }
    $reply .= " Sobre \"{$topic}\", posso avançar com próximos passos e reportar em sequência.";
    return $reply;
}

function agency_generate_conversation_id(): string
{
    return 'conv-' . gmdate('YmdHis') . '-' . substr(md5((string)microtime(true) . (string)mt_rand()), 0, 8);
}

function agency_sanitize_conversation_id(string $value): string
{
    $v = trim($value);
    if ($v === '') {
        return '';
    }
    $v = preg_replace('/[^a-zA-Z0-9._-]+/', '-', $v) ?? '';
    return trim($v, '-');
}

/**
 * @param array<string, mixed> $session
 * @return array<string, mixed>
 */
function agency_add_session_message(array $session, string $role, string $speaker, string $text, string $agentSlug = ''): array
{
    if (!isset($session['messages']) || !is_array($session['messages'])) {
        $session['messages'] = [];
    }
    $messages = $session['messages'];
    $messages[] = [
        'at' => agency_now_iso(),
        'role' => $role,
        'speaker' => $speaker,
        'agent_slug' => $agentSlug,
        'text' => $text,
    ];
    if (count($messages) > 120) {
        $messages = array_slice($messages, -120);
    }
    $session['messages'] = array_values($messages);
    return $session;
}

/**
 * Handles /api/agencia-chat
 */
function agency_handle_chat_api(string $docRoot): bool
{
    if (strtoupper($_SERVER['REQUEST_METHOD'] ?? 'GET') !== 'POST') {
        return renderJson(['ok' => false, 'error' => 'METHOD_NOT_ALLOWED'], 405);
    }

    $remoteAddr = (string)($_SERVER['REMOTE_ADDR'] ?? '');
    if (!in_array($remoteAddr, ['127.0.0.1', '::1'], true)) {
        return renderJson(['ok' => false, 'error' => 'LOCALHOST_ONLY'], 403);
    }

    $rawBody = file_get_contents('php://input');
    $payload = [];
    if (is_string($rawBody) && trim($rawBody) !== '') {
        $decoded = json_decode($rawBody, true);
        if (is_array($decoded)) {
            $payload = $decoded;
        }
    }

    $message = trim((string)($payload['message'] ?? ''));
    if ($message === '') {
        return renderJson(['ok' => false, 'error' => 'EMPTY_MESSAGE'], 400);
    }

    $conversationId = agency_sanitize_conversation_id((string)($payload['conversation_id'] ?? ''));
    if ($conversationId === '') {
        $conversationId = agency_generate_conversation_id();
    }

    $userId = agency_sanitize_conversation_id((string)($payload['user_id'] ?? 'default'));
    if ($userId === '') {
        $userId = 'default';
    }

    agency_append_event(
        $docRoot,
        'request_received',
        'info',
        'Mensagem recebida pela orquestração da Agência 3D.',
        [
            'conversation_id' => $conversationId,
            'user_id' => $userId,
            'preview' => agency_text_substr($message, 0, 160),
        ]
    );

    $memory = agency_load_memory($docRoot);
    if (!isset($memory['users'][$userId]) || !is_array($memory['users'][$userId])) {
        $memory['users'][$userId] = [];
    }
    $preferredName = trim((string)($memory['users'][$userId]['preferred_name'] ?? ''));

    $newPreferredName = agency_detect_preferred_name_command($message);
    if ($newPreferredName !== null && $newPreferredName !== '') {
        $memory['users'][$userId]['preferred_name'] = $newPreferredName;
        $memory['users'][$userId]['updated_at'] = agency_now_iso();
        $preferredName = $newPreferredName;
        agency_append_event(
            $docRoot,
            'user_memory_updated',
            'success',
            'Preferência de nome do usuário atualizada.',
            [
                'conversation_id' => $conversationId,
                'user_id' => $userId,
                'preferred_name' => $preferredName,
            ]
        );
    }

    if (!isset($memory['sessions'][$conversationId]) || !is_array($memory['sessions'][$conversationId])) {
        $memory['sessions'][$conversationId] = [
            'conversation_id' => $conversationId,
            'user_id' => $userId,
            'created_at' => agency_now_iso(),
            'updated_at' => agency_now_iso(),
            'messages' => [],
        ];
    }
    $session = $memory['sessions'][$conversationId];
    $session = agency_add_session_message($session, 'user', 'Voce', $message);
    $session['updated_at'] = agency_now_iso();

    $agents = agency_load_registry_agents($docRoot);
    if (count($agents) === 0) {
        agency_append_event(
            $docRoot,
            'routing_failed',
            'error',
            'Registry de agentes vazio durante orquestração.',
            ['conversation_id' => $conversationId]
        );
        return renderJson(['ok' => false, 'error' => 'REGISTRY_EMPTY'], 500);
    }

    $routing = agency_select_responders($agents, $message);
    $responders = $routing['responders'];
    $topicDepartments = $routing['topic_departments'];
    $responsibilityQuestion = (bool)$routing['responsibility_question'];
    $leaders = agency_build_department_leaders($agents);

    agency_append_event(
        $docRoot,
        'routing_selected',
        'info',
        'Roteamento de agentes concluído.',
        [
            'conversation_id' => $conversationId,
            'mentions' => $routing['mentions'],
            'mention_all' => (bool)$routing['mention_all'],
            'topic_departments' => $topicDepartments,
            'responsibility_question' => $responsibilityQuestion,
            'responders' => array_map(static fn(array $a): string => (string)$a['slug'], $responders),
        ]
    );

    $modelConfig = agency_model_config();
    agency_append_event(
        $docRoot,
        'model_strategy',
        $modelConfig['enabled'] ? 'info' : 'warn',
        $modelConfig['enabled']
            ? 'Modelo de resposta rica habilitado para orquestracao.'
            : 'Modelo indisponivel; fallback local de respostas ativado.',
        [
            'conversation_id' => $conversationId,
            'enabled' => (bool)$modelConfig['enabled'],
            'provider' => (string)$modelConfig['provider'],
            'model' => (string)$modelConfig['model'],
        ]
    );

    $responses = [];
    foreach ($responders as $index => $agent) {
        $context = agency_load_agent_context($docRoot, $agent);
        $dept = agency_department_for_agent($agent);
        $leaderSlug = isset($leaders[$dept]) ? (string)$leaders[$dept]['slug'] : '';
        $isLeader = $leaderSlug !== '' && $leaderSlug === (string)$agent['slug'];

        agency_append_event(
            $docRoot,
            'context_loaded',
            'info',
            'Contexto do agente carregado para resposta.',
            [
                'conversation_id' => $conversationId,
                'agent' => $agent['name'],
                'agent_slug' => $agent['slug'],
                'department' => $dept,
                'role' => $context['role'] ?? '',
            ]
        );

        agency_append_event(
            $docRoot,
            'model_request_started',
            'info',
            'Gerando resposta rica do agente via modelo.',
            [
                'conversation_id' => $conversationId,
                'agent' => $agent['name'],
                'agent_slug' => $agent['slug'],
                'provider' => (string)$modelConfig['provider'],
                'model' => (string)$modelConfig['model'],
            ]
        );

        $modelResult = agency_generate_agent_reply_with_model(
            $modelConfig,
            $agent,
            $context,
            $message,
            $topicDepartments,
            $responsibilityQuestion,
            $preferredName,
            $isLeader,
            $session
        );

        $source = 'fallback';
        if ((bool)$modelResult['ok']) {
            $text = (string)$modelResult['text'];
            $source = 'model';
            agency_append_event(
                $docRoot,
                'model_response_received',
                'success',
                'Resposta rica recebida do modelo.',
                [
                    'conversation_id' => $conversationId,
                    'agent' => $agent['name'],
                    'agent_slug' => $agent['slug'],
                    'provider' => (string)$modelResult['provider'],
                    'model' => (string)$modelResult['model'],
                ]
            );
        } else {
            $text = agency_build_agent_reply(
                $agent,
                $context,
                $message,
                $topicDepartments,
                $responsibilityQuestion,
                $preferredName,
                $isLeader
            );
            agency_append_event(
                $docRoot,
                'model_response_failed',
                'warn',
                'Falha no modelo; resposta local de contingencia aplicada.',
                [
                    'conversation_id' => $conversationId,
                    'agent' => $agent['name'],
                    'agent_slug' => $agent['slug'],
                    'provider' => (string)$modelResult['provider'],
                    'model' => (string)$modelResult['model'],
                    'error' => (string)$modelResult['error'],
                ]
            );
        }

        $responses[] = [
            'order' => $index + 1,
            'agent_slug' => (string)$agent['slug'],
            'agent_name' => (string)$agent['name'],
            'department' => $dept,
            'department_label' => agency_department_label($dept),
            'source' => $source,
            'provider' => (string)$modelResult['provider'],
            'model' => (string)$modelResult['model'],
            'text' => $text,
        ];

        $session = agency_add_session_message($session, 'assistant', (string)$agent['name'], $text, (string)$agent['slug']);
        $session['updated_at'] = agency_now_iso();

        agency_append_event(
            $docRoot,
            'response_ready',
            'success',
            'Resposta do agente gerada.',
            [
                'conversation_id' => $conversationId,
                'agent' => $agent['name'],
                'agent_slug' => $agent['slug'],
                'order' => $index + 1,
                'source' => $source,
            ]
        );
    }

    $memory['sessions'][$conversationId] = $session;
    agency_save_memory($docRoot, $memory);

    agency_append_event(
        $docRoot,
        'request_completed',
        'success',
        'Orquestração finalizada e memória persistida.',
        [
            'conversation_id' => $conversationId,
            'responses' => count($responses),
        ]
    );

    return renderJson(
        [
            'ok' => true,
            'conversation_id' => $conversationId,
            'user_id' => $userId,
            'preferred_name' => $preferredName,
            'routing' => [
                'mentions' => $routing['mentions'],
                'mention_all' => (bool)$routing['mention_all'],
                'topic_departments' => $topicDepartments,
                'responsibility_question' => $responsibilityQuestion,
                'responders' => array_map(static fn(array $a): string => (string)$a['slug'], $responders),
            ],
            'responses' => $responses,
            'monitor_url' => 'http://127.0.0.1:8095/admin-memoria-squad.html',
        ],
        200
    );
}
