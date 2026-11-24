#!/usr/bin/env python3
"""Gera o avaliacao.md a partir de lista-usuarios.txt, tarefas.json e notas.json.

Uso (o workflow já faz isso):
    GITHUB_TOKEN=... GITHUB_REPOSITORY=dono/repo python3 .github/workflows/avaliacao/avaliar.py

Só usa a biblioteca padrão. Se a API do GitHub falhar, o script termina com erro
e NÃO sobrescreve o avaliacao.md (melhor tabela velha do que tabela errada).
Os números dos alunos nunca são impressos nem gravados na saída.
"""
from __future__ import annotations

import json
import os
import re
import sys
import urllib.error
import urllib.request
from pathlib import Path

DIR = Path(__file__).resolve().parent
RAIZ = DIR.parents[2]  # .github/workflows/avaliacao -> raiz do repositório
USUARIO_RE = re.compile(r"^[A-Za-z0-9](?:[A-Za-z0-9-]{0,38})$")
CHECK = "✅"


# ───────────────────────── API do GitHub ─────────────────────────
class GitHub:
    def __init__(self, repo: str, token: str | None):
        self.repo, self.token = repo, token
        self._cache: dict = {}

    def _get(self, caminho: str):
        req = urllib.request.Request(
            "https://api.github.com" + caminho,
            headers={
                "Accept": "application/vnd.github+json",
                "X-GitHub-Api-Version": "2022-11-28",
                "User-Agent": "avaliacao-sdtr",
                **({"Authorization": f"Bearer {self.token}"} if self.token else {}),
            },
        )
        try:
            with urllib.request.urlopen(req, timeout=30) as r:
                return r.status, json.load(r)
        except urllib.error.HTTPError as e:
            if e.code == 404:
                return 404, None
            raise RuntimeError(f"GitHub API {e.code} em {caminho}") from e

    def _paginar(self, caminho: str) -> list:
        itens, pagina = [], 1
        while True:
            sep = "&" if "?" in caminho else "?"
            status, dados = self._get(f"{caminho}{sep}per_page=100&page={pagina}")
            itens += dados
            if len(dados) < 100:
                return itens
            pagina += 1

    def _memo(self, chave: str, fabrica):
        if chave not in self._cache:
            self._cache[chave] = fabrica()
        return self._cache[chave]

    def conta_existe(self, usuario: str) -> bool:
        return self._memo(f"u:{usuario.lower()}", lambda: self._get(f"/users/{usuario}")[0] == 200)

    def forks(self) -> set[str]:
        return self._memo("forks", lambda: {
            f["owner"]["login"].lower() for f in self._paginar(f"/repos/{self.repo}/forks")})

    def _pulls(self) -> list:
        return self._memo("pulls", lambda: self._paginar(f"/repos/{self.repo}/pulls?state=all"))

    def autores_pr(self, so_mesclados: bool = False) -> set[str]:
        return {p["user"]["login"].lower() for p in self._pulls()
                if p.get("user") and (p.get("merged_at") or not so_mesclados)}

    def autores_issue(self) -> set[str]:
        itens = self._memo("issues", lambda: self._paginar(f"/repos/{self.repo}/issues?state=all"))
        return {i["user"]["login"].lower() for i in itens if "pull_request" not in i and i.get("user")}

    def autores_commit(self) -> set[str]:
        itens = self._memo("commits", lambda: self._paginar(f"/repos/{self.repo}/commits"))
        return {c["author"]["login"].lower() for c in itens if c.get("author")}


# ───────────────────────── Verificações ─────────────────────────
# Cada verificação recebe (api, usuario) e devolve True/False.
# Para criar uma nova, acrescente uma linha aqui e use o nome em tarefas.json.
VERIFICACOES = {
    "conta":       lambda api, u: api.conta_existe(u),
    "fork":        lambda api, u: u.lower() in api.forks(),
    "pr":          lambda api, u: u.lower() in api.autores_pr(),
    "pr_mesclado": lambda api, u: u.lower() in api.autores_pr(so_mesclados=True),
    "issue":       lambda api, u: u.lower() in api.autores_issue(),
    "commit":      lambda api, u: u.lower() in api.autores_commit(),
}


# ───────────────────────── Entrada ─────────────────────────
def normalizar_usuario(texto: str) -> str:
    u = re.sub(r"^(https?://)?(www\.)?github\.com/", "", texto.strip(), flags=re.I)
    return u.strip("/").lstrip("@")


def ler_lista(caminho: Path):
    """Devolve (usuarios_unicos, total_de_alunos). Linhas: '<número> [usuário]'."""
    usuarios: dict[str, str] = {}
    total = 0
    for n, linha in enumerate(caminho.read_text(encoding="utf-8").splitlines(), 1):
        partes = linha.split()
        if not partes or not partes[0].isdigit():
            continue  # cabeçalho ou linha em branco
        total += 1
        if len(partes) < 2:
            continue
        usuario = normalizar_usuario(partes[1])
        if not USUARIO_RE.match(usuario):
            print(f"aviso: linha {n} da lista tem usuário inválido; ignorada", file=sys.stderr)
            continue
        if usuario.lower() in usuarios:
            print(f"aviso: usuário repetido na lista: {usuario}", file=sys.stderr)
            continue
        usuarios[usuario.lower()] = usuario
    return sorted(usuarios.values(), key=str.lower), total


def ler_notas(caminho: Path) -> dict[str, dict[str, float]]:
    bruto = json.loads(caminho.read_text(encoding="utf-8")) if caminho.exists() else {}
    return {u.lower(): v for u, v in bruto.items() if not u.startswith("_")}


def fmt(x: float) -> str:
    return (f"{x:.2f}".rstrip("0").rstrip(".") or "0").replace(".", ",")


# ───────────────────────── Saída ─────────────────────────
def gerar_markdown(cfg, usuarios, total_alunos, feitas, notas) -> str:
    tarefas = cfg["tarefas"]
    max_total = sum(t.get("pontos") or 0 for t in tarefas)
    mostrar_nota = any(t.get("pontos") is not None for t in tarefas) or bool(notas)

    cab = ["Aluno"] + [t["titulo"] for t in tarefas]
    if mostrar_nota:
        cab.append(f"Nota total (de {fmt(max_total)})" if max_total else "Nota total")
    linhas = ["| " + " | ".join(cab) + " |",
              "|:--|" + ":-:|" * (len(cab) - 1)]

    for u in usuarios:
        celulas = [f"[{u}](https://github.com/{u})"]
        total = 0.0
        for t in tarefas:
            feita = feitas[u][t["id"]]
            celulas.append(CHECK if feita else "")
            manual = notas.get(u.lower(), {}).get(t["id"])
            if manual is not None:
                total += float(manual)
            elif feita and t.get("pontos"):
                total += float(t["pontos"])
        if mostrar_nota:
            celulas.append(fmt(total))
        linhas.append("| " + " | ".join(celulas) + " |")

    sem_usuario = total_alunos - len(usuarios)
    saida = [
        "# Avaliação",
        "",
        "> Arquivo gerado automaticamente pelo workflow "
        "[`avaliacao.yml`](.github/workflows/avaliacao.yml). Não edite à mão: "
        "as alterações serão sobrescritas.",
        "",
        *linhas,
        "",
        f"{CHECK} = tarefa concluída. "
        f"{len(usuarios)} de {total_alunos} alunos já registraram o usuário em `lista-usuarios.txt` "
        f"({sem_usuario} ainda não).",
        "",
        "## Tarefas",
        "",
        *[f"- **{t['titulo']}** — {t['descricao']}" for t in tarefas],
        "",
    ]
    return "\n".join(saida)


def main() -> int:
    cfg = json.loads((DIR / "tarefas.json").read_text(encoding="utf-8"))
    for t in cfg["tarefas"]:
        desconhecidas = [v for v in t["verificacoes"] if v not in VERIFICACOES]
        if desconhecidas:
            print(f"erro: verificação desconhecida em {t['id']}: {desconhecidas}", file=sys.stderr)
            return 2

    repo = os.environ.get("GITHUB_REPOSITORY")
    if not repo:
        print("erro: defina GITHUB_REPOSITORY (dono/repositório)", file=sys.stderr)
        return 2
    api = GitHub(repo, os.environ.get("GITHUB_TOKEN"))

    usuarios, total_alunos = ler_lista(RAIZ / cfg["lista"])
    notas = ler_notas(DIR / "notas.json")
    feitas = {u: {t["id"]: all(VERIFICACOES[v](api, u) for v in t["verificacoes"])
                  for t in cfg["tarefas"]} for u in usuarios}

    conteudo = gerar_markdown(cfg, usuarios, total_alunos, feitas, notas)
    (RAIZ / cfg["saida"]).write_text(conteudo, encoding="utf-8")
    print(f"{cfg['saida']} atualizado: {len(usuarios)} alunos com usuário, "
          f"{total_alunos} na lista.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
