# Preferências do usuário

> Este arquivo é **do usuário**. O instalador do omyfedora nunca o sobrescreve.
> O agente deve ler este arquivo no início de cada tarefa. Se estiver vazio ou ausente, vale o padrão (perguntar sempre).

## Confirmação de edição de configuração pessoal

modo-config: perguntar

Valores:

- `perguntar` (padrão): pergunta antes de **toda** edição de config (niri, Noctalia, shell, terminal).
- `so-risco`: edita direto mudanças pequenas e reversíveis (cores, gaps, tamanhos, um atalho novo que não troque um existente), sempre com backup e validação. Continua perguntando para: monitores, remover/trocar atalhos padrão, `spawn`/`spawn-at-startup`, blocos grandes.

**Instalar, remover e serviços sempre perguntam, em qualquer modo.**

## Notas pessoais

(Anote aqui coisas que o agente deve lembrar sobre este computador: monitores, preferências de atalhos, apps favoritos...)
