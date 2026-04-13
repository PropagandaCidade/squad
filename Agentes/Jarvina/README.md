# Jarvina - Voice Assistant Coordinator

## Visao geral
Jarvina atua no departamento de Tecnologia e Produto como coordenadora de voz em tempo real.
O foco e manter a experiencia live estavel, com resposta rapida, seguranca de sessao e qualidade de audio.

## Missao ativa
- Produto: JARVINA LIVE (Web + Railway + Gemini Live)
- Objetivo: conversacao por voz confiavel, sem regressao de autenticacao, websocket e retorno do modelo

## Como executar
```powershell
.\runner\Jarvina.ps1 -Suite full-live
```

## Modo 2 repositorios (SQUAD + JARVINA)
Quando o SQUAD estiver em repo separado, configure no Railway da Jarvina:

- `SQUAD_REPO_URL=https://github.com/PropagandaCidade/squad.git`
- `SQUAD_REPO_REF=main`
- `SQUAD_AGENTS_JSON_PATH=Agentes/agents-scores.json`

Opcional (forca URL exata do JSON):

- `SQUAD_AGENTS_JSON_URL=https://raw.githubusercontent.com/PropagandaCidade/squad/main/Agentes/agents-scores.json`

Notas:
- Se `SQUAD_TOTAL_AGENTS` estiver definido, ele vira override manual.
- Sem override, a Jarvina tenta ler total de agentes via GitHub raw e cai para fallback local/padrao se necessario.

## Estrutura local
- `config/agent-config.json`: perfil oficial, regras de execucao e parametros de agente
- `config/local.json`: preferencias locais de operacao
- `config/projects.json`: projeto e suites de validacao
- `checks/quality-gates.md`: gates de qualidade obrigatorios
- `tests/Jarvina-live-regression-checklist.md`: checklist manual de regressao live
- `playbooks/mission-playbook.md`: fluxo operacional padrao
- `reports/README.md`: padrao de evidencia e auditoria

## Memoria
- Working set ativo: `memory-enterprise/60_AGENT_MEMORY/working_sets/assistant.yaml`
- Profile ativo: `memory-enterprise/60_AGENT_MEMORY/profiles/assistant.yaml`
- Alias dedicado: `memory-enterprise/60_AGENT_MEMORY/working_sets/jarvina.yaml`
- Alias dedicado: `memory-enterprise/60_AGENT_MEMORY/profiles/jarvina.yaml`

## Gamificacao
Toda entrega deve registrar pontos e heartbeat via modulo `Agentes/Gamificacao`.
