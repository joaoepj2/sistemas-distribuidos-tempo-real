# Aula: DNS dinâmico com BIND9 — do servidor à sala de aula

*Série de experimentos: BIND9 no WSL e no Docker, zona com atualização dinâmica (RFC 2136) protegida por TSIG, e alunos alterando a zona ao vivo pelo notebook ou pelo smartphone.*

## Objetivos

- Subir o BIND9 como servidor autoritativo de uma zona própria (`sdtr.uniube`), **no WSL e em um contêiner Docker, com exatamente a mesma configuração**.
- Entender como funciona a atualização dinâmica: mensagem `UPDATE`, autenticação por chave TSIG, journal (`.jnl`).
- Inserir, consultar e remover registros com o servidor no ar, a partir de notebooks (`nsupdate` + `dig`) e de smartphones (navegador, via um pequeno gateway web).
- Observar, na prática, o que a pilha TCP/IP faz por baixo: UDP × TCP, porta 53 × porta alternativa, NAT e firewall.

## Arquitetura da sala

```
 notebook do aluno ── nsupdate / dig ───────────────┐
                                                    ▼
                                  ┌──────────── PC do professor ────────────┐
                                  │  BIND9 (WSL ou Docker)   porta 5300     │
 smartphone ── navegador ──► :8080 ─► gateway.py ──► (usa a chave TSIG) ─────┘
```

Decisões de projeto (vale discutir com a turma):

| Decisão | Motivo |
| --- | --- |
| Zona `sdtr.uniube` | `.test` é reservado (RFC 6761): nunca colide com um domínio real. Evite `.local` (conflita com mDNS). |
| Porta **5300** em vez de 53 | Evita conflito com `systemd-resolved`, Compartilhamento de Internet do Windows e afins. Também não usamos 5353, que é do mDNS. |
| `recursion no` | O servidor só responde pela própria zona; não vira resolvedor aberto na rede da escola. |
| Chave TSIG única (`aula-key`) | Simples para a primeira aula. O Experimento 10 evolui para uma chave por aluno. |

## Pré-requisitos

**Professor:** Windows 10/11 com WSL2 (Ubuntu 22.04 ou 24.04) e, para o caminho Docker, Docker Desktop com a integração com o WSL ativada. Todos os arquivos do laboratório são criados dentro do WSL.

**Alunos:** Linux/WSL com `sudo apt install dnsutils`, ou macOS com `brew install bind` (traz `dig` e `nsupdate`). Quem não tiver isso — e todos os smartphones — usa o gateway web do Experimento 9.

**Rede:** todos na mesma rede. Atenção: muitos Wi-Fi de escola têm *client isolation* (um aparelho não enxerga o outro). Se o Experimento 7 falhar por esse motivo, use o hotspot do celular do professor ou um roteador próprio da sala.

---

## Experimento 0 — Preparar o laboratório (comum aos dois caminhos)

No terminal do WSL:

```bash
sudo apt update
sudo apt install -y bind9 bind9-utils dnsutils python3-dnspython

mkdir -p ~/dns-lab && cd ~/dns-lab

# IP do notebook do professor NA REDE DA SALA (veja com `ipconfig` no Windows)
export IP_PROF=192.168.0.10
```

**1) Chave TSIG** (o arquivo já sai no formato do BIND):

```bash
tsig-keygen -a hmac-sha256 aula-key > aula.key
chmod 644 aula.key
cat aula.key
```

**2) Configuração do servidor** (`named.conf`):

```bash
cat > named.conf <<'EOF'
options {
    directory "/var/cache/bind";
    listen-on port 5300 { any; };
    listen-on-v6 { none; };
    allow-query { any; };
    recursion no;
    dnssec-validation no;
    querylog yes;
};

// Tudo no console, para projetar o log durante a aula
logging {
    channel console { stderr; severity info; print-time yes; };
    category default         { console; };
    category queries         { console; };
    category update          { console; };
    category update-security { console; };
};

include "/etc/bind/aula.key";

zone "sdtr.uniube" {
    type primary;
    file "/var/lib/bind/sdtr.uniube.zone";
    update-policy {
        grant aula-key zonesub ANY;   // essa chave pode mexer em qualquer nome da zona
    };
};
EOF
```

Uma zona só aceita atualização dinâmica se tiver `allow-update` **ou** `update-policy` (os dois ao mesmo tempo não é permitido). Usamos `update-policy` porque é ela que permite, mais adiante, restringir cada aluno ao seu próprio nome.

**3) Arquivo da zona** (`sdtr.uniube.zone`):

```bash
cat > sdtr.uniube.zone <<'EOF'
$TTL 60
@   IN SOA ns1.sdtr.uniube. admin.sdtr.uniube. (
        1        ; serial
        3600     ; refresh
        600      ; retry
        86400    ; expire
        60 )     ; TTL negativo
    IN NS  ns1.sdtr.uniube.
ns1       IN A IP_PROF
professor IN A IP_PROF
EOF
sed -i "s/IP_PROF/$IP_PROF/" sdtr.uniube.zone
```

Escolha **um** dos dois caminhos a seguir (os dois usam a porta 5300; pare um antes de subir o outro).

---

## Experimento 1 — BIND9 rodando no WSL

```bash
# Se o systemd estiver ativo no seu WSL, pare a instância padrão do pacote
sudo systemctl stop named 2>/dev/null

# Instala a configuração do laboratório nos locais que o pacote usa
sudo cp /etc/bind/named.conf /etc/bind/named.conf.orig
sudo cp named.conf /etc/bind/named.conf
sudo install -o root -g bind -m 640 aula.key /etc/bind/aula.key
sudo install -o bind -g bind -m 644 sdtr.uniube.zone /var/lib/bind/sdtr.uniube.zone
sudo mkdir -p /run/named && sudo chown bind:bind /run/named

# Valida antes de subir
sudo named-checkconf /etc/bind/named.conf
sudo named-checkzone sdtr.uniube /var/lib/bind/sdtr.uniube.zone

# Sobe em primeiro plano: o terminal vira o painel de log da aula
sudo named -g -u bind
```

Deixe esse terminal aberto (e projetado). Para parar: `Ctrl+C`. Abra um segundo terminal para os próximos experimentos.

**Pergunta para a turma:** por que o arquivo da zona fica em `/var/lib/bind` e não em `/etc/bind`? *(Resposta: o `named` precisa **gravar** na pasta da zona — journal e reescrita do arquivo — e `/etc` é, por convenção, só de configuração.)*

---

## Experimento 2 — O mesmo BIND9 em um contêiner Docker

Na pasta `~/dns-lab`:

```bash
cat > Dockerfile <<'EOF'
FROM ubuntu:24.04
RUN apt-get update \
 && apt-get install -y --no-install-recommends bind9 bind9-utils dnsutils \
 && rm -rf /var/lib/apt/lists/* \
 && mkdir -p /run/named && chown bind:bind /run/named
COPY named.conf /etc/bind/named.conf
COPY --chown=bind:bind sdtr.uniube.zone /var/lib/bind/sdtr.uniube.zone
EXPOSE 5300/udp 5300/tcp
CMD ["named", "-g", "-u", "bind"]
EOF

docker build -t aula-bind9 .

# A chave fica FORA da imagem (montada só leitura); os dados da zona ficam em um volume
docker volume rm bind-data 2>/dev/null
docker run -d --name bind9 \
  -p 5300:5300/udp -p 5300:5300/tcp \
  -v "$PWD/aula.key:/etc/bind/aula.key:ro" \
  -v bind-data:/var/lib/bind \
  aula-bind9

docker logs -f bind9     # painel de log da aula
```

Pontos para discutir: a imagem é a mesma para qualquer máquina, mas **segredo** (chave) e **estado** (zona alterada pelos alunos) ficam fora dela. Apagar o volume (`docker volume rm bind-data`) devolve a zona ao estado inicial — é o botão de "reset" da aula.

---

## Experimento 3 — O servidor está vivo? (consultas)

Daqui em diante os comandos valem para os dois caminhos. No segundo terminal:

```bash
export DNS=127.0.0.1     # na sala, os alunos usam o IP do professor

dig @$DNS -p 5300 sdtr.uniube SOA +short
dig @$DNS -p 5300 sdtr.uniube NS  +short
dig @$DNS -p 5300 professor.sdtr.uniube A +short
```

Observe no painel de log as consultas chegando. Repare no **serial** do SOA (ainda `1`) — vamos vê-lo mudar.

gitNote que `sdtr.uniube` não é delegada por ninguém: só funciona porque dissemos ao `dig` exatamente para qual servidor perguntar (`@IP -p 5300`).

---

## Experimento 4 — Atualização sem chave é recusada

```bash
nsupdate <<EOF
server $DNS 5300
zone sdtr.uniube
update add intruso.sdtr.uniube. 60 A 6.6.6.6
send
EOF
```

Resultado esperado: `update failed: REFUSED`. No log aparece uma mensagem de `update-security` explicando a recusa. Ou seja: **dinâmica não significa aberta** — a zona só aceita quem provar que conhece a chave.

---

## Experimento 5 — Inserir, consultar e remover (com TSIG)

**Inserir:**

```bash
nsupdate -k aula.key <<EOF
server $DNS 5300
zone sdtr.uniube
update add joao.sdtr.uniube. 60 A 10.1.1.1
update add joao.sdtr.uniube. 60 TXT "aluno do 3o periodo"
send
EOF
```

**Consultar:**

```bash
dig @$DNS -p 5300 joao.sdtr.uniube A   +noall +answer
dig @$DNS -p 5300 joao.sdtr.uniube TXT +noall +answer
dig @$DNS -p 5300 sdtr.uniube SOA +short     # o serial subiu sozinho
```

**Alterar** (apagar + inserir na mesma mensagem — o servidor aplica tudo ou nada):

```bash
nsupdate -k aula.key <<EOF
server $DNS 5300
zone sdtr.uniube
update delete joao.sdtr.uniube. A
update add    joao.sdtr.uniube. 60 A 10.2.2.2
send
EOF
```

**Remover:**

```bash
nsupdate -k aula.key <<EOF
server $DNS 5300
zone sdtr.uniube
update delete joao.sdtr.uniube. TXT
update delete joao.sdtr.uniube. A
send
EOF

dig @$DNS -p 5300 joao.sdtr.uniube A    # status: NXDOMAIN
```

(`update delete nome.` sem tipo remove todos os registros daquele nome.)

---

## Experimento 6 — O que o servidor fez por baixo?

Faça duas ou três atualizações e então olhe a pasta da zona.

```bash
# WSL:
ls -l /var/lib/bind
# Docker:
docker exec bind9 ls -l /var/lib/bind
```

Vai aparecer `sdtr.uniube.zone.jnl` — o **journal**: o BIND não reescreve o arquivo da zona a cada alteração, apenas anexa as mudanças ao journal (rápido e seguro contra queda de energia).

```bash
# WSL:
sudo named-journalprint /var/lib/bind/sdtr.uniube.zone.jnl
# Docker:
docker exec bind9 named-journalprint /var/lib/bind/sdtr.uniube.zone.jnl
```

A saída mostra cada alteração com os registros `del`/`add` e a troca de serial do SOA. Compare com o arquivo da zona (`cat`): ele **ainda está com o conteúdo antigo**. Para consolidar o journal no arquivo:

```bash
sudo rndc sync -clean sdtr.uniube        # WSL
docker exec bind9 rndc sync -clean sdtr.uniube   # Docker
```

Se `rndc` reclamar de chave ou conexão, pule esta parte — o restante da aula não depende dela.

Depois do `sync`, o `.jnl` some e o arquivo da zona passa a conter os registros criados pelos alunos. Isso explica um erro clássico: **editar o arquivo da zona à mão com o servidor rodando** perde alterações ou é sobrescrito. O caminho seguro é `rndc freeze`, editar, `rndc thaw`.

---

## Experimento 7 — Abrindo o servidor para a sala

**7.1 Descobrir o IP** que os alunos vão usar: o IP do **Windows** na rede da sala (`ipconfig`), não o do WSL.

**7.2 Liberar no Firewall do Windows** (PowerShell como administrador):

```powershell
New-NetFirewallRule -DisplayName "DNS lab UDP" -Direction Inbound -Protocol UDP -LocalPort 5300 -Action Allow
New-NetFirewallRule -DisplayName "DNS lab TCP" -Direction Inbound -Protocol TCP -LocalPort 5300,8080 -Action Allow
```

**7.3 Caminho Docker Desktop:** as portas publicadas (`-p 5300:5300`) já ficam acessíveis na rede, em UDP e TCP. Nada mais a fazer.

**7.4 Caminho WSL puro:** por padrão o WSL2 fica atrás de um NAT, e os aparelhos da sala **não** alcançam o `named`. Duas saídas:

- **Modo espelhado** (Windows 11 com WSL recente): em `C:\Users\<voce>\.wslconfig` coloque

  ```
  [wsl2]
  networkingMode=mirrored
  ```

  e execute `wsl --shutdown`. O WSL passa a compartilhar o IP do Windows. Pode ser necessário liberar também no firewall do Hyper-V; esse detalhe muda entre versões, então confira a documentação do WSL.
- **`netsh portproxy`** (PowerShell como administrador):

  ```powershell
  $wsl = (wsl hostname -I).Split(" ")[0]
  netsh interface portproxy add v4tov4 listenport=5300 listenaddress=0.0.0.0 connectport=5300 connectaddress=$wsl
  ```

  **Pegadinha didática:** o `portproxy` só encaminha **TCP**. Nesse modo os alunos precisam forçar TCP: `dig +tcp ...` e `nsupdate -v`. Ótimo momento para retomar a diferença entre UDP e TCP: o DNS funciona sobre os dois, e o cliente só consegue usar TCP se o servidor e o caminho aceitarem.

**7.5 Distribuir a chave** (apenas para quem usará `nsupdate`). Em uma pasta que contenha **somente** `aula.key`:

```bash
mkdir ~/chave && cp ~/dns-lab/aula.key ~/chave && cd ~/chave
python3 -m http.server 8000
```

Cada aluno executa `curl -O http://$IP_PROF:8000/aula.key`. Quando todos tiverem, encerre o servidor com `Ctrl+C`. (Compartilhar um segredo assim só é aceitável em laboratório isolado; depois da aula gere uma chave nova.)

**7.6 Teste de fumaça de cada aluno:**

```bash
export DNS=192.168.0.10      # IP do professor
dig @$DNS -p 5300 professor.sdtr.uniube A +short
```

---

## Experimento 8 — Alunos nos notebooks

Cada aluno cria um registro com o **seu usuário do github** (evita colisões), consulta o do colega e remove o seu:

```bash
NOME=maria      # cada um usa o seu

nsupdate -k aula.key <<EOF
server $DNS 5300
zone sdtr.uniube
update add $NOME.sdtr.uniube. 60 A 10.0.0.$((RANDOM % 200 + 20))
send
EOF

dig @$DNS -p 5300 $NOME.sdtr.uniube A +short
dig @$DNS -p 5300 joao.sdtr.uniube  A +short     # registro de um colega
```

No painel projetado, a turma vê as mensagens `update` e as consultas chegando, com o IP de origem de cada aluno.

**Atividade:** Quem consegue criar um CNAME `www.sdtr.uniube` apontando para o seu nome?" — e o segundo aluno a tentar descobre que **CNAME não pode coexistir com outros registros do mesmo nome**.

---

## Experimento 9 — Smartphones: um gateway web

Celulares não têm `nsupdate`. Em vez de pedir que instalem algo, o professor roda um mini-servidor web que recebe o formulário e faz a atualização DNS **em nome do aluno**. Bônus de segurança: a chave TSIG nunca sai do computador do professor.

Salve como `gateway.py` (no mesmo lugar em que o BIND roda ou na máquina que o enxerga em `127.0.0.1:5300`):

```python
#!/usr/bin/env python3
"""gateway.py — formulário web para alterar a zona sdtr.uniube pelo celular."""
import os, re, html
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs
import dns.update, dns.query, dns.resolver, dns.tsigkeyring, dns.rcode

ZONA    = "sdtr.uniube"
SERVER  = os.environ.get("DNS_SERVER", "127.0.0.1")
PORTA   = int(os.environ.get("DNS_PORT", "5300"))
keyring = dns.tsigkeyring.from_text({"aula-key": os.environ["TSIG_SECRET"]})
NOME_OK = re.compile(r"^[a-z0-9]([a-z0-9-]{0,40}[a-z0-9])?$")
TIPOS   = {"A", "AAAA", "TXT", "CNAME"}

PAGINA = """<!doctype html><meta charset=utf-8>
<meta name=viewport content="width=device-width,initial-scale=1">
<title>DNS da sala</title>
<body style="font-family:sans-serif;max-width:30rem;margin:1rem auto;padding:0 1rem">
<h2>Zona sdtr.uniube</h2>
<form method=post>
<p><input name=nome placeholder="seu nome" required> .sdtr.uniube</p>
<p><select name=tipo><option>A<option>AAAA<option>TXT<option>CNAME</select>
<input name=valor placeholder="valor (ex: 10.0.0.5)"></p>
<p><button name=acao value=add>Inserir</button>
<button name=acao value=get>Consultar</button>
<button name=acao value=del>Remover</button></p>
</form>
<pre>{msg}</pre>"""

def executar(acao, nome, tipo, valor):
    if not NOME_OK.match(nome) or tipo not in TIPOS:
        return "nome ou tipo inválido"
    fqdn = f"{nome}.{ZONA}."
    try:
        if acao == "get":
            r = dns.resolver.Resolver(configure=False)
            r.nameservers, r.port = [SERVER], PORTA
            return "\n".join(x.to_text() for x in r.resolve(fqdn, tipo))
        upd = dns.update.Update(ZONA, keyring=keyring)
        if acao == "add":
            if tipo == "TXT":
                valor = '"' + valor.replace('"', "") + '"'
            if tipo == "CNAME" and not valor.endswith("."):
                valor += "."
            upd.add(fqdn, 60, tipo, valor)
        elif acao == "del":
            upd.delete(fqdn, tipo)
        else:
            return "ação desconhecida"
        resp = dns.query.tcp(upd, SERVER, port=PORTA, timeout=5)
        return f"{acao} {fqdn} {tipo}: {dns.rcode.to_text(resp.rcode())}"
    except Exception as e:
        return f"{type(e).__name__}: {e}"

class H(BaseHTTPRequestHandler):
    def _resp(self, msg=""):
        corpo = PAGINA.format(msg=html.escape(msg)).encode()
        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(corpo)))
        self.end_headers()
        self.wfile.write(corpo)
    def do_GET(self):
        self._resp()
    def do_POST(self):
        n = int(self.headers.get("Content-Length", 0))
        f = parse_qs(self.rfile.read(n).decode())
        g = lambda k: f.get(k, [""])[0].strip()
        self._resp(executar(g("acao"), g("nome").lower(), g("tipo"), g("valor")))

ThreadingHTTPServer(("0.0.0.0", 8080), H).serve_forever()
```

Execute (a chave é lida do `aula.key`):

```bash
cd ~/dns-lab
TSIG_SECRET=$(grep secret aula.key | cut -d'"' -f2) python3 gateway.py
```

Os alunos abrem `http://IP_DO_PROFESSOR:8080` no celular, escolhem tipo `A`, escrevem o próprio nome e um IP, e tocam em **Inserir**. Depois **Consultar** e **Remover**. Resposta `NOERROR` = a zona foi alterada; `REFUSED`, `NXRRSET` etc. mostram o código DNS real devolvido pelo servidor.

O gateway usa TCP para falar com o BIND (por isso funciona mesmo com `portproxy`). Ele não tem login — é um brinquedo de laboratório; não o exponha fora da sala.

**Pergunta:** o que o gateway faz que o `nsupdate` do notebook também faz? *(Monta a mesma mensagem DNS `UPDATE`, assinada com TSIG; só muda quem segura a chave.)*

---

## Experimento 10 — Desafios para quem terminar antes

**10.1 Criar só se não existir (pré-requisito).** Peça a dois alunos que rodem ao mesmo tempo:

```bash
nsupdate -k aula.key <<EOF
server $DNS 5300
zone sdtr.uniube
prereq nxdomain disputado.sdtr.uniube.
update add disputado.sdtr.uniube. 60 A 10.9.9.9
send
EOF
```

O primeiro recebe sucesso; o segundo recebe `update failed: YXDOMAIN`. A verificação e a escrita acontecem juntas no servidor, sem a corrida "consultei, estava livre, aí outro criou".

**10.2 Uma chave por aluno, cada um no seu subdomínio.** Gere chaves individuais:

```bash
for n in 01 02 03; do tsig-keygen -a hmac-sha256 aluno$n; done > alunos.key
```

Inclua o arquivo no `named.conf` (`include "/etc/bind/alunos.key";`) e troque a política:

```
update-policy {
    grant aluno01 subdomain aluno01.sdtr.uniube. ANY;
    grant aluno02 subdomain aluno02.sdtr.uniube. ANY;
    grant aluno03 subdomain aluno03.sdtr.uniube. ANY;
};
```

Agora `aluno01` consegue criar `site.aluno01.sdtr.uniube`, mas recebe `REFUSED` ao tentar mexer no nome de `aluno02`. (No Docker, monte também o `alunos.key`, como foi feito com `aula.key`, e reinicie o contêiner; no WSL, reinicie o `named`.)

**10.3 Ver o `UPDATE` no fio.** No Wireshark, capture na interface de rede, filtre `udp.port == 5300`, clique com o botão direito em um pacote → *Decode As… → DNS*. Compare o `Opcode: Update` com uma consulta comum e localize o registro **TSIG** no final da mensagem.

**10.4 Listar a zona inteira (AXFR).**

```bash
dig @$DNS -p 5300 sdtr.uniube AXFR
```

Mostra tudo que a turma criou — e por que, em produção, `allow-transfer` deve ser restrito.

---

## Encerramento e limpeza

```bash
# Docker: parar e voltar a zona ao estado inicial
docker rm -f bind9 && docker volume rm bind-data

# WSL: parar o named (Ctrl+C no terminal) e restaurar a configuração original
sudo cp /etc/bind/named.conf.orig /etc/bind/named.conf
sudo rm -f /var/lib/bind/aula.test.zone* /etc/bind/aula.key

# Windows (PowerShell admin): remover as regras criadas
Remove-NetFirewallRule -DisplayName "DNS lab UDP","DNS lab TCP"
netsh interface portproxy delete v4tov4 listenport=5300 listenaddress=0.0.0.0
```

Apague também o `aula.key` distribuído: ele deixou de ser segredo.

---

## Problemas comuns

| Sintoma | Causa provável | O que fazer |
| --- | --- | --- |
| `update failed: REFUSED` | Sem chave, chave errada ou nome fora da `update-policy` | Conferir `-k aula.key` e o log (`update-security`) |
| `tsig verify failure` / `BADTIME` | Relógios com mais de \~5 min de diferença | No WSL: `sudo hwclock -s`; nos notebooks, sincronizar data e hora |
| `NOTAUTH` | Zona errada na linha `zone` | Usar `zone aula.test` |
| Tempo esgotado só de outros aparelhos | Firewall, IP errado, *client isolation* ou NAT do WSL2 | Ver Experimento 7; testar `dig +tcp` |
| Funciona no professor e não na rede (WSL) | `portproxy` só encaminha TCP | `dig +tcp` e `nsupdate -v`, ou modo espelhado |
| `named` não sobe | Erro de sintaxe, `/run/named` ausente, porta em uso | `named-checkconf`; `ss -lntup \| grep 5300`; `docker logs bind9` |
| `SERVFAIL` depois de um update | Pasta da zona sem permissão de escrita | `/var/lib/bind` deve pertencer a `bind` |
| Alterei o arquivo da zona e nada mudou | Existe um `.jnl` pendente | `rndc sync -clean` antes, ou `rndc freeze`/`thaw` |

---

## Sugestão de roteiro (2 aulas de 50 min)

| Bloco | Conteúdo | Tempo |
| --- | --- | --- |
| 1 | Conceito: zona, SOA, serial, atualização dinâmica, TSIG | 15 min |
| 2 | Exp. 0 a 3 — subir o servidor (WSL ou Docker) e consultar | 25 min |
| 3 | Exp. 4 a 6 — recusa sem chave, add/replace/delete, journal | 25 min |
| 4 | Exp. 7 e 8 — abrir para a sala; alunos nos notebooks | 20 min |
| 5 | Exp. 9 — smartphones pelo gateway | 10 min |
| 6 | Exp. 10 (desafios) e discussão | 5 min + extras |

Se o tempo apertar, mostre o WSL **ou** o Docker ao vivo e deixe o outro como tarefa de casa: como a configuração é a mesma, o aluno só reaproveita os arquivos do Experimento 0.

## Perguntas de fixação

1. Qual é a diferença entre `allow-update` e `update-policy`? Por que uma zona dinâmica sem nenhuma das duas recusa tudo?
2. Por que o serial do SOA muda sozinho a cada atualização, e por que isso importa para servidores secundários?
3. O que o journal guarda e por que o arquivo da zona não é reescrito a cada alteração?
4. Por que o `portproxy` do Windows quebra o `dig` padrão, e o que muda ao usar `+tcp`?
5. Se a chave TSIG estivesse em cada celular, o que poderia dar errado? Que vantagem tem a arquitetura do gateway?

## Observações de segurança

- Este laboratório é para **rede isolada**. Não publique a porta 5300 nem o gateway na internet.
- A chave compartilhada serve para uma aula; gere outra a cada turma e apague as antigas.
- O gateway não autentica os alunos e valida apenas formato de nome e tipo de registro. É um recurso didático, não um serviço de produção.
