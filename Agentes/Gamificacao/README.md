# Gamificacao dos Agentes

Este modulo centraliza a pontuacao, niveis, badges e tarefas dos agentes do Squad.

## Arquivo canonico

- O placar oficial fica em `Agentes/agents-scores.json`.
- O arquivo `Agentes/Gamificacao/agents-scores.json` e mantido em sincronia para compatibilidade legada.

## Funcoes principais

- `Add-AgentPoints`: adiciona pontos diretamente.
- `Register-AgentAction`: pontuacao automatica por categoria, complexidade e resultado.
- `Get-AgentScore`: consulta score de um agente.
- `Get-Leaderboard`: ranking dos melhores pontuadores.

## Exemplo de integracao em runner

```powershell
. "../Gamificacao/gamification.ps1"
Register-AgentAction -AgentName "Marcos" -Task "Validacao Studio Master" -Category "validation" -Complexity "high" -Outcome "success"
```

## Registro rapido via CLI

Use o script utilitario:

```powershell
.\register-task.ps1 -AgentName "Ricardo" -Task "Hotfix de waveform" -Category "hotfix" -Complexity "critical"
```

Ou com pontos manuais:

```powershell
.\register-task.ps1 -AgentName "Valentina" -Task "Diagnostico UX" -Points 15 -Badges @("UX Visionario")
```
