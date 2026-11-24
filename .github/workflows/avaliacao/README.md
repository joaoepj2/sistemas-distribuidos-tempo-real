# Avaliação automática

O workflow `../avaliacao.yml` roda `avaliar.py`, que gera `avaliacao.md` na raiz.
Roda a cada push na `main`, quando um PR ou issue é aberto/fechado, de 6 em 6 horas e manualmente (aba Actions → Avaliação → Run workflow).

| Arquivo | Função |
|---|---|
| `avaliar.py` | Lê a lista, consulta a API do GitHub, escreve a tabela |
| `tarefas.json` | Define as tarefas (colunas), pontos e verificações |
| `notas.json` | Notas dadas à mão, por usuário e tarefa |

Linhas da tabela: alunos que registraram o usuário em `lista-usuarios.txt`. O número do aluno nunca vai para a tabela, nem para o log.

## Adicionar uma tarefa
Acrescente um objeto em `tarefas.json`:

```json
{ "id": "tarefa-2", "titulo": "Tarefa 2", "descricao": "Abrir uma issue reservando o tema.",
  "pontos": null, "verificacoes": ["issue"] }
```

Verificações disponíveis (a tarefa vale ✅ quando **todas** passam):
`conta` (usuário existe), `fork` (tem fork do repositório), `pr` (abriu PR, aberto ou mesclado), `pr_mesclado`, `issue` (abriu issue), `commit` (autor de commit no repositório).
Para criar outra, acrescente uma linha no dicionário `VERIFICACOES` de `avaliar.py`.

## Notas
- Com `"pontos": 10` em uma tarefa, quem a conclui ganha 10 automaticamente.
- Nota manual em `notas.json` substitui a automática: `{"fulano": {"tarefa-1": 7.5}}`.
- A coluna **Nota total** aparece assim que alguma tarefa tiver `pontos` ou `notas.json` tiver entradas.
