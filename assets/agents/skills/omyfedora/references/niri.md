# niri — configuração e validação

## Arquivos

- **Config do usuário:** `~/.config/niri/config.kdl` (instalada uma vez pelo omyfedora; é do usuário).
- **Fallback do projeto:** `/etc/xdg/niri/config.kdl` (sobrescrito na atualização; **não edite**).
- O niri **recarrega a config ao salvar**. Não é preciso reiniciar a sessão.

## Fluxo seguro de edição

```bash
# 1. backup (ver seguranca.md)
# 2. editar o arquivo
# 3. validar ANTES de considerar pronto
niri validate
# 4. se falhar: restaurar o backup imediatamente e avisar o usuário
```

`niri validate` aceita um caminho de config (confira com `niri validate --help`). Valide uma cópia editada antes de substituir o arquivo real quando a mudança for grande.

Se o niri recarregar uma config inválida, ele mostra um aviso na tela e mantém a anterior. Mesmo assim, não dependa disso: valide antes.

## Sintaxe (KDL)

- Comentários: `//` em linha; `/-` na frente de um nó o desativa (`/-binds { ... }`).
- Blocos principais: `input`, `output`, `layout`, `binds`, `window-rule`, `spawn-at-startup`, `environment`, `prefer-no-csd`.
- Confira sempre a documentação da versão instalada (`niri --version`; wiki do niri) antes de usar uma opção que você não tem certeza que existe. **Não invente chaves.**

Exemplos (adapte à versão instalada):

```kdl
layout {
    gaps 8
}

binds {
    Mod+T { spawn "alacritty"; }
}

output "eDP-1" {
    scale 1.25
}
```

## Monitores

- Liste com `niri msg outputs` (nomes, modos, escala, posição). Use os nomes exatos que ele mostrar.
- Mudar modo, escala ou posição pode deixar o monitor sem imagem. **Sempre peça confirmação** e deixe o backup à mão.
- O atalho `Super+P` do omyfedora abre o controle de monitores do Noctalia. Se o usuário só quer ajustar rapidamente, sugira isso antes de editar arquivo.
- O repositório tem `pessoal-pc.sh` como exemplo de layout via `niri msg`. É pessoal, não use como base.

## Atalhos padrão do omyfedora

`Super+T` terminal · `Super+Space` launcher · `Super+S` control center · `Super+P` monitores.
Antes de **remover ou trocar** um desses, avise: o usuário pode perder o acesso ao terminal ou ao launcher.

## Comandos que executam coisas (tratar como execução de código)

`spawn "..."` em `binds`, `spawn-at-startup "..."` e `environment` rodam comandos na sessão do usuário, de forma persistente. Mostre o comando exato na confirmação, mesmo no modo de confirmação reduzida.
Nunca coloque ali nada baixado ou copiado de fonte externa sem o usuário ler.

## Depois de mudar

Peça ao usuário para conferir visualmente. Se algo estiver errado, restaure o backup (`cp -a` do backup para o original) e valide de novo.
