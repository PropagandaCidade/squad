import os
import json
import re
import base64
import asyncio
import traceback
import threading
from datetime import datetime, timezone
from typing import Any, Dict, Optional, Tuple
from urllib.parse import urlparse
from urllib.request import Request, urlopen

from fastapi import FastAPI, WebSocket, WebSocketDisconnect
from fastapi.middleware.cors import CORSMiddleware
from starlette.websockets import WebSocketState

# DB (opcional)
import mysql.connector

# Gemini (Google GenAI SDK)
from google import genai
from google.genai import types


# =========================
# APP
# =========================
app = FastAPI()

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# =========================
# ENV / CONFIG
# =========================
GEMINI_API_KEY = os.environ.get("GEMINI_API_KEY") or os.environ.get("GOOGLE_API_KEY") or ""

# IMPORTANTE:
# - Para Live + áudio, use um modelo "live/native audio".
# - Você já tem a env GEMINI_LIVE_MODEL_ID no Railway; vamos respeitar.
RAW_GEMINI_LIVE_MODEL_ID = os.environ.get("GEMINI_LIVE_MODEL_ID") or "gemini-2.5-flash-native-audio-preview-12-2025"

# Voz (Jarvina feminina)
VOICE_NAME = os.environ.get("GEMINI_VOICE_NAME", "Kore")

# DB via env (Railway variables)
DB_HOST = os.environ.get("DB_HOST", "")
DB_NAME = os.environ.get("DB_NAME", "")
DB_USER = os.environ.get("DB_USER", "")
DB_PASSWORD = os.environ.get("DB_PASSWORD", "")
DB_PORT = int(os.environ.get("DB_PORT", "3306"))
ALLOWED_WS_ORIGINS = {
    origin.strip()
    for origin in os.environ.get("ALLOWED_WS_ORIGINS", "").split(",")
    if origin.strip()
}
STRICT_ADMIN_VALIDATION = os.environ.get("STRICT_ADMIN_VALIDATION", "0").strip().lower() in {"1", "true", "yes"}
STRICT_ORIGIN_VALIDATION = os.environ.get("STRICT_ORIGIN_VALIDATION", "0").strip().lower() in {"1", "true", "yes"}


def normalize_live_model_id(raw_model_id: str) -> str:
    model_id = (raw_model_id or "").strip()
    if model_id.startswith("models/"):
        model_id = model_id[len("models/") :]
    return model_id or "gemini-2.5-flash-native-audio-preview-12-2025"


GEMINI_LIVE_MODEL_ID = normalize_live_model_id(RAW_GEMINI_LIVE_MODEL_ID)
JARVINA_SYSTEM_PROFILE = (os.environ.get("JARVINA_SYSTEM_PROFILE") or "").strip()
JARVINA_PLAYBOOK_HINT = (os.environ.get("JARVINA_PLAYBOOK_HINT") or "").strip()
JARVINA_WORKSPACE_ROOT = (os.environ.get("JARVINA_WORKSPACE_ROOT") or "").strip()
SQUAD_REPO_URL = (os.environ.get("SQUAD_REPO_URL") or "").strip()
SQUAD_REPO_REF = (os.environ.get("SQUAD_REPO_REF") or "").strip()
SQUAD_AGENTS_JSON_URL = (os.environ.get("SQUAD_AGENTS_JSON_URL") or "").strip()
SQUAD_AGENTS_JSON_PATH = (os.environ.get("SQUAD_AGENTS_JSON_PATH") or "").strip()
JARVINA_MEMORY_FILE = os.environ.get("JARVINA_MEMORY_FILE") or os.path.join(
    os.path.dirname(__file__), "jarvina-memory.json"
)

# Cliente GenAI
client = genai.Client(
    api_key=GEMINI_API_KEY,
    # Em geral, v1beta é o mais compatível pra live
    http_options={"api_version": "v1beta"},
)


# =========================
# HELPERS
# =========================
def get_db_config() -> Optional[Dict[str, Any]]:
    if not (DB_HOST and DB_NAME and DB_USER and DB_PASSWORD):
        return None
    return {
        "host": DB_HOST,
        "user": DB_USER,
        "password": DB_PASSWORD,
        "database": DB_NAME,
        "port": DB_PORT,
        "connect_timeout": 10,
    }


def parse_admin_token(raw_token: Any) -> Optional[int]:
    if isinstance(raw_token, bool):
        return None

    if isinstance(raw_token, int):
        token = raw_token
    elif isinstance(raw_token, str):
        value = raw_token.strip()
        if not value or not value.isdigit():
            return None
        token = int(value)
    else:
        return None

    if token <= 0 or token > 2147483647:
        return None

    return token


def get_admin_name(admin_id: int) -> Tuple[str, bool]:
    cfg = get_db_config()
    if not cfg:
        # Fallback para ambientes sem DB configurado.
        return "admin", True

    try:
        db = mysql.connector.connect(**cfg)
        cursor = db.cursor(dictionary=True)
        cursor.execute("SELECT username FROM admins WHERE id = %s", (admin_id,))
        row = cursor.fetchone()
        cursor.close()
        db.close()

        if row and row.get("username"):
            return str(row["username"]), True

        return "admin", False
    except Exception as e:
        print(f"(Aviso) Falha ao ler admin no MySQL: {e}")
        return "admin", False


_db_memory_schema_ready = False
_memory_file_lock = threading.Lock()
_PREFERRED_NAME_PATTERNS = [
    re.compile(
        r"\b(?:me\s+cham(?:e|a)|pode\s+me\s+chamar|quero\s+que\s+me\s+chame|me\s+chame\s+sempre)\s+de\s+(.+)$",
        re.IGNORECASE,
    ),
    re.compile(r"\bmeu\s+nome\s+(?:e|é)\s+(.+)$", re.IGNORECASE),
]


def _ensure_db_memory_table(conn: Any) -> None:
    global _db_memory_schema_ready
    if _db_memory_schema_ready:
        return

    cursor = conn.cursor()
    cursor.execute(
        """
        CREATE TABLE IF NOT EXISTS jarvina_admin_memory (
            admin_id INT NOT NULL PRIMARY KEY,
            preferred_name VARCHAR(120) NULL,
            updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
        )
        """
    )
    conn.commit()
    cursor.close()
    _db_memory_schema_ready = True


def _load_file_memory() -> Dict[str, Any]:
    if not JARVINA_MEMORY_FILE:
        return {}
    if not os.path.exists(JARVINA_MEMORY_FILE):
        return {}

    try:
        with open(JARVINA_MEMORY_FILE, "r", encoding="utf-8") as f:
            data = json.load(f)
        return data if isinstance(data, dict) else {}
    except Exception:
        return {}


def _save_file_memory(data: Dict[str, Any]) -> None:
    if not JARVINA_MEMORY_FILE:
        return

    folder = os.path.dirname(JARVINA_MEMORY_FILE)
    if folder:
        os.makedirs(folder, exist_ok=True)

    tmp_path = f"{JARVINA_MEMORY_FILE}.tmp"
    with open(tmp_path, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
    os.replace(tmp_path, JARVINA_MEMORY_FILE)


def _normalize_preferred_name(raw_name: str) -> Optional[str]:
    if not isinstance(raw_name, str):
        return None

    name = raw_name.strip().strip("\"'`´“”‘’")
    if not name:
        return None

    # Corta anexos comuns de frase.
    name = re.split(r"[,.;!?]", name, maxsplit=1)[0].strip()
    name = re.split(r"(?i)\b(?:por favor|obrigado|obrigada|ok|tudo bem)\b", name, maxsplit=1)[0].strip()
    name = " ".join(name.split())

    if len(name) < 2:
        return None
    if len(name) > 60:
        name = name[:60].rstrip()

    if not re.match(r"^[A-Za-zÀ-ÿ][A-Za-zÀ-ÿ0-9._' -]*$", name):
        return None

    return name


def extract_preferred_name_command(user_text: str) -> Optional[str]:
    if not isinstance(user_text, str):
        return None

    text = user_text.strip()
    if not text:
        return None

    for pattern in _PREFERRED_NAME_PATTERNS:
        match = pattern.search(text)
        if not match:
            continue
        candidate = _normalize_preferred_name(match.group(1))
        if candidate:
            return candidate

    return None


def get_admin_preferred_name(admin_id: int) -> Optional[str]:
    cfg = get_db_config()
    if cfg:
        try:
            db = mysql.connector.connect(**cfg)
            _ensure_db_memory_table(db)
            cursor = db.cursor(dictionary=True)
            cursor.execute(
                "SELECT preferred_name FROM jarvina_admin_memory WHERE admin_id = %s",
                (admin_id,),
            )
            row = cursor.fetchone()
            cursor.close()
            db.close()
            if row and row.get("preferred_name"):
                return _normalize_preferred_name(str(row["preferred_name"]))
        except Exception as e:
            print(f"(Aviso) Falha ao ler memoria Jarvina no MySQL: {e}")

    with _memory_file_lock:
        data = _load_file_memory()
        admins = data.get("admins", {}) if isinstance(data, dict) else {}
        record = admins.get(str(admin_id), {}) if isinstance(admins, dict) else {}
        preferred_name = record.get("preferred_name")
        if isinstance(preferred_name, str):
            return _normalize_preferred_name(preferred_name)
    return None


def save_admin_preferred_name(admin_id: int, preferred_name: str) -> bool:
    normalized = _normalize_preferred_name(preferred_name)
    if not normalized:
        return False

    cfg = get_db_config()
    if cfg:
        try:
            db = mysql.connector.connect(**cfg)
            _ensure_db_memory_table(db)
            cursor = db.cursor()
            cursor.execute(
                """
                INSERT INTO jarvina_admin_memory (admin_id, preferred_name)
                VALUES (%s, %s)
                ON DUPLICATE KEY UPDATE
                    preferred_name = VALUES(preferred_name),
                    updated_at = CURRENT_TIMESTAMP
                """,
                (admin_id, normalized),
            )
            db.commit()
            cursor.close()
            db.close()
            return True
        except Exception as e:
            print(f"(Aviso) Falha ao salvar memoria Jarvina no MySQL: {e}")

    with _memory_file_lock:
        data = _load_file_memory()
        if not isinstance(data, dict):
            data = {}
        admins = data.get("admins")
        if not isinstance(admins, dict):
            admins = {}
            data["admins"] = admins

        admins[str(admin_id)] = {
            "preferred_name": normalized,
            "updated_at": datetime.now(timezone.utc).isoformat(),
        }
        _save_file_memory(data)
    return True


def extract_user_turn_texts(payload: Dict[str, Any]) -> list[str]:
    if not isinstance(payload, dict):
        return []

    texts = []

    def _collect(parts: Any) -> None:
        if not isinstance(parts, list):
            return
        for part in parts:
            if not isinstance(part, dict):
                continue
            text = part.get("text")
            if isinstance(text, str) and text.strip():
                texts.append(text.strip())

    candidates = []
    server_content = payload.get("serverContent") or payload.get("server_content")
    if isinstance(server_content, dict):
        candidates.append(server_content)

    candidates.append(payload)

    for base in candidates:
        user_turn = base.get("userTurn") or base.get("user_turn")
        if not isinstance(user_turn, dict):
            continue
        _collect(user_turn.get("parts"))

    # Dedup preservando ordem
    deduped = []
    seen = set()
    for text in texts:
        if text in seen:
            continue
        deduped.append(text)
        seen.add(text)
    return deduped


def _make_serializable(obj: Any) -> Any:
    """Converte bytes -> base64 e percorre dict/list recursivamente."""
    if isinstance(obj, (bytes, bytearray)):
        return base64.b64encode(bytes(obj)).decode("utf-8")
    if isinstance(obj, dict):
        return {k: _make_serializable(v) for k, v in obj.items()}
    if isinstance(obj, list):
        return [_make_serializable(v) for v in obj]
    return obj


def _decode_b64(s: str) -> bytes:
    return base64.b64decode(s.encode("utf-8"))


def _extract_realtime_audio(msg: Dict[str, Any]) -> Tuple[int, int, list]:
    """
    Retorna:
      (chunks_count, bytes_total, chunks_list)
    chunks_list: [(audio_bytes, mime_type), ...]
    """
    rt = msg.get("realtime_input") or {}
    media_chunks = rt.get("media_chunks") or []
    total_bytes = 0
    chunks_ok = []

    for c in media_chunks:
        if not isinstance(c, dict):
            continue
        data_b64 = c.get("data")
        mime_type = c.get("mime_type") or c.get("mimeType")
        if not data_b64 or not mime_type:
            continue
        try:
            audio_bytes = _decode_b64(data_b64)
            total_bytes += len(audio_bytes)
            chunks_ok.append((audio_bytes, mime_type))
        except Exception:
            continue

    return (len(chunks_ok), total_bytes, chunks_ok)


def _safe_json(obj: Any) -> str:
    return json.dumps(obj, ensure_ascii=False)


def _read_positive_int_env(name: str, default: int) -> int:
    raw = (os.environ.get(name) or "").strip()
    if not raw:
        return default


def _read_positive_int_env_optional(name: str) -> Optional[int]:
    raw = (os.environ.get(name) or "").strip()
    if not raw:
        return None
    try:
        value = int(raw)
        return value if value > 0 else None
    except Exception:
        return None


def _parse_github_repo_slug(repo_url: str) -> Optional[Tuple[str, str]]:
    if not repo_url:
        return None

    # Aceita:
    # - https://github.com/owner/repo.git
    # - https://github.com/owner/repo
    # - git@github.com:owner/repo.git
    match = re.search(r"github\.com[:/]+([^/]+)/([^/]+?)(?:\.git)?/?$", repo_url.strip(), re.IGNORECASE)
    if not match:
        return None

    owner = (match.group(1) or "").strip()
    repo = (match.group(2) or "").strip()
    if not owner or not repo:
        return None
    return (owner, repo)


def _build_squad_agents_json_candidates() -> list[str]:
    urls = []
    seen = set()

    def _add(url: str) -> None:
        normalized = (url or "").strip()
        if not normalized or normalized in seen:
            return
        seen.add(normalized)
        urls.append(normalized)

    if SQUAD_AGENTS_JSON_URL:
        _add(SQUAD_AGENTS_JSON_URL)

    slug = _parse_github_repo_slug(SQUAD_REPO_URL)
    if slug:
        owner, repo = slug
        refs = []
        if SQUAD_REPO_REF:
            refs.append(SQUAD_REPO_REF)
        refs.extend(["main", "master"])

        paths = []
        if SQUAD_AGENTS_JSON_PATH:
            paths.append(SQUAD_AGENTS_JSON_PATH.strip().lstrip("/"))
        paths.extend(
            [
                "Agentes/agents-scores.json",
                "Agentes/Gamificacao/agents-scores.json",
            ]
        )

        for ref in refs:
            clean_ref = (ref or "").strip().strip("/")
            if not clean_ref:
                continue
            for path in paths:
                clean_path = (path or "").strip().lstrip("/")
                if not clean_path:
                    continue
                _add(f"https://raw.githubusercontent.com/{owner}/{repo}/{clean_ref}/{clean_path}")

    return urls


def _extract_agents_total(data: Any) -> Optional[int]:
    source = data.get("agents") if isinstance(data, dict) else data
    if isinstance(source, dict) and source:
        return len(source)
    if isinstance(source, list) and source:
        return len(source)
    return None


def _read_agents_total_from_remote(default_total: int) -> int:
    for url in _build_squad_agents_json_candidates():
        try:
            request = Request(
                url,
                headers={
                    "User-Agent": "jarvina-live/1.0",
                    "Accept": "application/json",
                },
            )
            with urlopen(request, timeout=8) as response:
                if getattr(response, "status", 200) != 200:
                    continue
                body = response.read()

            payload = json.loads(body.decode("utf-8"))
            total = _extract_agents_total(payload)
            if total and total > 0:
                print(f"--- SQUAD total lido do remoto: {total} ({url}) ---")
                return total
        except Exception:
            continue

    return default_total
    try:
        value = int(raw)
        return value if value > 0 else default
    except Exception:
        return default


def _read_agents_total_from_workspace(default_total: int) -> int:
    root = (JARVINA_WORKSPACE_ROOT or "").strip()
    if not root:
        return default_total
    if not os.path.exists(root):
        return default_total

    candidate_files = [
        os.path.join(root, "Agentes", "agents-scores.json"),
        os.path.join(root, "Agentes", "Gamificacao", "agents-scores.json"),
    ]

    for file_path in candidate_files:
        if not os.path.exists(file_path):
            continue
        try:
            with open(file_path, "r", encoding="utf-8") as f:
                data = json.load(f)
            source = data.get("agents") if isinstance(data, dict) else data
            if isinstance(source, dict) and source:
                return len(source)
        except Exception:
            continue

    return default_total


SQUAD_TOTAL_AGENTS_OVERRIDE = _read_positive_int_env_optional("SQUAD_TOTAL_AGENTS")
if SQUAD_TOTAL_AGENTS_OVERRIDE:
    SQUAD_TOTAL_AGENTS = SQUAD_TOTAL_AGENTS_OVERRIDE
else:
    SQUAD_TOTAL_AGENTS = _read_agents_total_from_remote(_read_agents_total_from_workspace(37))
SQUAD_TOTAL_DEPARTMENTS = _read_positive_int_env("SQUAD_TOTAL_DEPARTMENTS", 8)


def build_system_instruction(user_name: str, preferred_name: Optional[str] = None) -> str:
    """
    Prompt operacional da Jarvina para manter respostas alinhadas ao contexto live.
    """
    sections = []

    if JARVINA_SYSTEM_PROFILE:
        sections.append(JARVINA_SYSTEM_PROFILE)

    display_name = preferred_name or user_name

    sections.extend(
        [
            "Voce e a JARVINA, assistente de elite do SQUAD Propaganda Cidade.",
            f"Atenda o administrador {display_name}.",
            "Responda sempre em Portugues do Brasil, com tom natural, objetivo e colaborativo.",
            "Use saudacao neutra 'Ola' por padrao e nao use automaticamente bom dia/boa tarde/boa noite.",
            "Contexto ativo: sessao autenticada, websocket live conectado e telemetria de audio em tempo real.",
            (
                f"Dado operacional atual do SQUAD: {SQUAD_TOTAL_AGENTS} agentes ativos "
                f"e {SQUAD_TOTAL_DEPARTMENTS} departamentos."
            ),
            (
                f"Regra fixa: quando perguntarem quantos agentes existem no SQUAD, "
                f"responda exatamente '{SQUAD_TOTAL_AGENTS} agentes ativos'."
            ),
            "Nao diga que esta sem acesso sistemico da Jarvina.",
            "Se faltar dado externo fora da sessao atual, diga qual dado falta e proponha o proximo passo pratico.",
            "Prioridades: autenticacao valida, estabilidade WS, audio no backend, fechamento de turno e resposta do modelo.",
            (
                "Playbook Jarvina: 1) validar sessao admin; 2) validar WS/setup; "
                "3) validar audio chegando no backend; 4) validar end_of_turn e resposta do modelo; "
                "5) validar playback sem loop/travamento; 6) orientar registro de evidencias."
            ),
        ]
    )

    if JARVINA_PLAYBOOK_HINT:
        sections.append(f"Playbook adicional: {JARVINA_PLAYBOOK_HINT}")

    if preferred_name:
        sections.append(
            (
                f"Preferencia persistida do admin: trate SEMPRE por '{preferred_name}' "
                f"e nao use 'admin' no lugar desse nome, ate nova orientacao."
            )
        )

    if JARVINA_WORKSPACE_ROOT and os.path.exists(JARVINA_WORKSPACE_ROOT):
        sections.append(f"Raiz sistemica configurada para operacao local: {JARVINA_WORKSPACE_ROOT}.")
    elif SQUAD_REPO_URL:
        sections.append(f"Base sistemica remota configurada em: {SQUAD_REPO_URL}.")

    return " ".join(part for part in sections if part)


# =========================
# ROUTES
# =========================
@app.get("/")
async def health_check():
    return {
        "status": "JARVINA_LIVE_READY",
        "model": GEMINI_LIVE_MODEL_ID,
        "voice": VOICE_NAME,
    }


@app.websocket("/ws/live")
async def websocket_endpoint(websocket: WebSocket):
    request_origin = (websocket.headers.get("origin") or "").strip()
    request_origin_host = ""
    if request_origin:
        try:
            request_origin_host = (urlparse(request_origin).hostname or "").strip().lower()
        except Exception:
            request_origin_host = ""

    is_local_origin = request_origin_host in {"localhost", "127.0.0.1", "::1"}

    if ALLOWED_WS_ORIGINS:
        if request_origin not in ALLOWED_WS_ORIGINS:
            if STRICT_ORIGIN_VALIDATION and not is_local_origin:
                print(f"(Bloqueado) Origin nao permitido no WS: {request_origin}")
                await websocket.close(code=1008, reason="ORIGIN_NOT_ALLOWED")
                return
            print(f"(Aviso) Origin fora da allowlist, mantendo sessao: {request_origin}")

    await websocket.accept()

    user_name = "admin"
    admin_token = None
    preferred_name = None

    # métricas mic (pra debug no Network > WS)
    mic_chunks = 0
    mic_bytes = 0

    # flags de atividade
    speaking = False

    # sinal de encerramento
    stop_event = asyncio.Event()
    session_close_code = 1000
    session_close_reason = "SESSION_ENDED"

    async def ws_send_json(payload: Dict[str, Any]) -> None:
        """Envia JSON e se o WS estiver fechado, encerra silenciosamente."""
        if stop_event.is_set():
            return
        try:
            await websocket.send_text(_safe_json(payload))
        except Exception:
            stop_event.set()

    async def close_websocket_if_open(code: int = 1000, reason: str = "SESSION_ENDED") -> None:
        try:
            if websocket.application_state == WebSocketState.CONNECTED:
                await websocket.close(code=code, reason=reason)
        except Exception:
            pass

    try:
        # =========================
        # 1) SETUP do browser (primeira msg)
        # =========================
        raw_setup = await websocket.receive_text()

        try:
            setup_params = json.loads(raw_setup) if raw_setup else {}
        except json.JSONDecodeError:
            await ws_send_json({
                "type": "error",
                "code": "BAD_SETUP",
                "text": "Setup JSON invalido."
            })
            await websocket.close(code=1008, reason="BAD_SETUP")
            return

        admin_token = parse_admin_token(setup_params.get("admin_token"))
        if admin_token is None:
            if STRICT_ADMIN_VALIDATION and not is_local_origin:
                await ws_send_json({
                    "type": "error",
                    "code": "AUTH_FAILED",
                    "text": "Admin token invalido."
                })
                await websocket.close(code=1008, reason="AUTH_FAILED_TOKEN")
                return

            admin_token = 1
            user_name = "admin-local"
            print("(Aviso) Admin token invalido; seguindo em modo permissivo para origem local/integracao.")

        user_name, admin_exists = get_admin_name(admin_token)
        if not admin_exists:
            if STRICT_ADMIN_VALIDATION and not is_local_origin:
                await ws_send_json({
                    "type": "error",
                    "code": "AUTH_FAILED",
                    "text": "Admin nao autorizado."
                })
                await websocket.close(code=1008, reason="AUTH_FAILED_ADMIN")
                return

            # Modo permissivo para ambientes de integracao: segue com fallback.
            user_name = f"admin-{admin_token}"
            print(f"(Aviso) Admin nao encontrado no DB. Prosseguindo em modo permissivo: {user_name}")

        requested_preferred_name = _normalize_preferred_name(str(setup_params.get("preferred_name", "")))
        if requested_preferred_name and save_admin_preferred_name(admin_token, requested_preferred_name):
            preferred_name = requested_preferred_name

        print(f"--- Conexão Autorizada: {user_name} ---")

        if not preferred_name:
            preferred_name = get_admin_preferred_name(admin_token)
        if preferred_name:
            print(f"--- Memoria ativa: preferred_name={preferred_name} ---")
            await ws_send_json(
                {
                    "type": "memory_update",
                    "scope": "preferred_name",
                    "value": preferred_name,
                }
            )

        # =========================
        # 2) CONFIG LIVE (AUDIO + voz Kore)
        # =========================
        config = {
            "response_modalities": ["AUDIO"],
            "system_instruction": (
                f"Você é a JARVINA, assistente de elite do Voice Hub. "
                f"Atenda o administrador {user_name}. Responda sempre em Português do Brasil. "
                f"Seja natural, objetiva e útil."
            ),
            "speech_config": {
                "voice_config": {
                    "prebuilt_voice_config": {"voice_name": VOICE_NAME}
                }
            },
            # O client (browser) já faz VAD e envia end_of_turn.
            "realtime_input_config": {
                "automatic_activity_detection": {"disabled": True}
            },
        }

        config["system_instruction"] = build_system_instruction(user_name, preferred_name)

        # =========================
        # 3) CONECTA NO GEMINI LIVE
        # =========================
        async with client.aio.live.connect(model=GEMINI_LIVE_MODEL_ID, config=config) as session:
            print("--- Link Neural Estabelecido com Google ---")

            # =========================
            # TASK A) Browser -> Gemini
            # =========================
            async def browser_to_gemini():
                nonlocal speaking, mic_chunks, mic_bytes, session_close_code, session_close_reason, preferred_name
                has_audio_since_last_activity_end = False
                last_activity_end_at = 0.0
                try:
                    while not stop_event.is_set():
                        raw = await websocket.receive_text()
                        if not raw:
                            continue

                        try:
                            data = json.loads(raw)
                        except Exception:
                            continue

                        # cliente pode mandar close
                        if data.get("type") == "close":
                            session_close_code = 1000
                            session_close_reason = "CLIENT_CLOSE_REQUEST"
                            stop_event.set()
                            break

                        if data.get("type") == "memory_set":
                            requested_name = _normalize_preferred_name(str(data.get("preferred_name", "")))
                            if not requested_name:
                                await ws_send_json(
                                    {
                                        "type": "error",
                                        "code": "MEMORY_INVALID_NAME",
                                        "text": "Nome preferido invalido para memoria.",
                                    }
                                )
                                continue

                            if save_admin_preferred_name(admin_token, requested_name):
                                preferred_name = requested_name
                                await ws_send_json(
                                    {
                                        "type": "memory_update",
                                        "scope": "preferred_name",
                                        "value": preferred_name,
                                    }
                                )
                            continue

                        # fim de turno
                        end_of_turn = bool(data.get("end_of_turn")) or bool(data.get("endOfTurn"))

                        # áudio realtime
                        if "realtime_input" in data:
                            c_count, b_total, chunks_list = _extract_realtime_audio(data)
                            mic_chunks += c_count
                            mic_bytes += b_total

                            if c_count > 0:
                                has_audio_since_last_activity_end = True

                            # debug pro browser
                            await ws_send_json({
                                "type": "mic_debug",
                                "chunks": mic_chunks,
                                "bytes": mic_bytes,
                                "mime_type": "audio/pcm;rate=16000",
                                "end_of_turn": end_of_turn,
                            })

                            # se tem áudio e ainda não iniciou fala, manda activity_start
                            if c_count > 0 and not speaking:
                                speaking = True
                                try:
                                    await session.send_realtime_input(activity_start=types.ActivityStart())
                                except Exception:
                                    # se não suportar em algum build, segue sem
                                    pass

                            # envia cada chunk pro Gemini Live
                            for (audio_bytes, mime_type) in chunks_list:
                                try:
                                    blob = types.Blob(data=audio_bytes, mime_type=mime_type)
                                    await session.send_realtime_input(audio=blob)
                                except Exception as e:
                                    print(f"(Aviso) Falha ao enviar chunk ao Gemini: {e}")
                                    session_close_code = 1011
                                    session_close_reason = "UPSTREAM_SEND_ERROR"
                                    await ws_send_json({
                                        "type": "error",
                                        "code": "LIVE_BACKEND_ERROR",
                                        "text": "Falha no backend live: UPSTREAM_SEND_ERROR"
                                    })
                                    stop_event.set()
                                    break

                            if stop_event.is_set():
                                break

                        # Se o browser sinalizou fim do turno, fecha atividade (gera resposta)
                        if end_of_turn:
                            now_mono = asyncio.get_running_loop().time()
                            if (not has_audio_since_last_activity_end and not speaking):
                                continue
                            if (now_mono - last_activity_end_at) < 0.9:
                                continue
                            try:
                                await session.send_realtime_input(activity_end=types.ActivityEnd())
                                last_activity_end_at = now_mono
                                has_audio_since_last_activity_end = False
                            except Exception as e:
                                print(f"(Aviso) Falha activity_end: {e}")
                            speaking = False

                except WebSocketDisconnect:
                    session_close_code = 1000
                    session_close_reason = "CLIENT_DISCONNECTED"
                    stop_event.set()
                except asyncio.CancelledError:
                    stop_event.set()
                    return
                except Exception as e:
                    stop_event.set()
                    print(f"Erro Task A (browser_to_gemini): {e}")
                    traceback.print_exc()

            # =========================
            # TASK B) Gemini -> Browser
            # =========================
            async def gemini_to_browser():
                nonlocal session_close_code, session_close_reason, preferred_name
                try:
                    while not stop_event.is_set():
                        # No SDK Python, receive() pode finalizar por turno.
                        # Reabrimos o iterador para continuar a sessão.
                        received_any = False
                        async for msg in session.receive():
                            received_any = True
                            if stop_event.is_set():
                                break

                            payload = msg.model_dump(by_alias=True, exclude_none=True)
                            payload = _make_serializable(payload)

                            for user_text in extract_user_turn_texts(payload):
                                requested_name = extract_preferred_name_command(user_text)
                                if not requested_name:
                                    continue
                                if preferred_name and requested_name.lower() == preferred_name.lower():
                                    continue
                                if save_admin_preferred_name(admin_token, requested_name):
                                    preferred_name = requested_name
                                    print(
                                        f"--- Memoria atualizada: admin={admin_token} "
                                        f"preferred_name={preferred_name} ---"
                                    )
                                    await ws_send_json(
                                        {
                                            "type": "memory_update",
                                            "scope": "preferred_name",
                                            "value": preferred_name,
                                        }
                                    )

                            # Se o websocket já fechou, não tenta enviar (evita erro ASGI)
                            try:
                                await websocket.send_text(_safe_json(payload))
                            except Exception:
                                stop_event.set()
                                break

                        if stop_event.is_set():
                            break

                        # Evita loop quente se um turno vier vazio.
                        if not received_any:
                            await asyncio.sleep(0.03)

                except asyncio.CancelledError:
                    stop_event.set()
                    return
                except Exception as e:
                    session_close_code = 1011
                    session_close_reason = "UPSTREAM_RECEIVE_ERROR"
                    await ws_send_json({
                        "type": "error",
                        "code": "LIVE_BACKEND_ERROR",
                        "text": "Falha no backend live: UPSTREAM_RECEIVE_ERROR"
                    })
                    stop_event.set()
                    print(f"Erro Task B (gemini_to_browser): {e}")
                    traceback.print_exc()

            # Coordena as duas tasks (browser->gemini e gemini->browser).
            task_a = asyncio.create_task(browser_to_gemini())
            task_b = asyncio.create_task(gemini_to_browser())

            while not stop_event.is_set():
                done, _ = await asyncio.wait(
                    {task_a, task_b},
                    return_when=asyncio.FIRST_COMPLETED
                )

                if task_a in done:
                    try:
                        await task_a
                    except asyncio.CancelledError:
                        pass
                    except Exception as e:
                        print(f"Erro Task A final: {e}")
                    stop_event.set()
                    break

                if task_b in done:
                    if task_b.cancelled():
                        session_close_code = 1011
                        session_close_reason = "UPSTREAM_RECEIVE_CANCELLED"
                        stop_event.set()
                        break

                    exc = task_b.exception()
                    if exc is not None:
                        raise exc

                    # Se terminar sem erro, task de receive saiu de forma inesperada.
                    if not stop_event.is_set():
                        session_close_code = 1011
                        session_close_reason = "UPSTREAM_RECEIVE_EXITED"
                        await ws_send_json({
                            "type": "error",
                            "code": "LIVE_BACKEND_ERROR",
                            "text": "Falha no backend live: UPSTREAM_RECEIVE_EXITED"
                        })
                        stop_event.set()
                        break

            await close_websocket_if_open(code=session_close_code, reason=session_close_reason)

            for t in {task_a, task_b}:
                if t.done():
                    continue
                t.cancel()
                try:
                    await t
                except asyncio.CancelledError:
                    pass
                except Exception:
                    pass

    except WebSocketDisconnect:
        pass
    except asyncio.CancelledError:
        stop_event.set()
        await close_websocket_if_open(code=1001, reason="SERVER_CANCELLED")
    except Exception as e:
        stop_event.set()
        print(f"FALHA CRÍTICA NO SETUP: {e}")
        traceback.print_exc()
        try:
            error_text = str(e).strip() or "Falha interna no backend live."
            await ws_send_json({
                "type": "error",
                "code": "LIVE_BACKEND_ERROR",
                "text": f"Falha no backend live: {error_text[:220]}"
            })
        except Exception:
            pass
        try:
            await close_websocket_if_open(code=1011, reason="LIVE_BACKEND_ERROR")
        except Exception:
            pass
    finally:
        print("--- SESSÃO FINALIZADA ---")
        # Nao forca close aqui para nao sobrescrever codigos de fechamento
        # enviados anteriormente (ex.: 1008/1011). O servidor fecha ao sair.


if __name__ == "__main__":
    import uvicorn
    port = int(os.environ.get("PORT", "8080"))
    uvicorn.run(app, host="0.0.0.0", port=port)
