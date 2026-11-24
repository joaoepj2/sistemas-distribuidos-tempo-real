# Tutorial: OpenLDAP 2.6 no Debian

Base do diretório: `dc=sdtr,dc=uniube,dc=br`
Ramos: `ou=pessoas` e `ou=grupos`

> **Versão:** o OpenLDAP 2.6 vem no **Debian 13 (trixie)**, pacote `slapd` 2.6.x.
> O Debian 12 (bookworm) traz a 2.5. Confira com `apt policy slapd` antes de começar.
> Os comandos abaixo funcionam igual nas duas versões.

---

## 1. Conceitos rápidos

| Termo | Significa |
|---|---|
| LDAP | Protocolo para consultar e alterar um diretório (uma árvore de dados). |
| DIT | A árvore. Começa na raiz e abre em ramos. |
| DN | Nome único de uma entrada. Ex.: `uid=maria,ou=pessoas,dc=sdtr,dc=uniube,dc=br` |
| RDN | A primeira parte do DN. Ex.: `uid=maria` |
| LDIF | Arquivo de texto usado para descrever entradas. |
| `slapd` | O servidor OpenLDAP. |
| `ldap-utils` | Os comandos de cliente: `ldapadd`, `ldapsearch`, `ldapmodify`, `ldapdelete`. |

A árvore que vamos montar:

```text
dc=sdtr,dc=uniube,dc=br
├── cn=admin                      (administrador)
├── ou=pessoas
│   ├── uid=maria
│   └── uid=joao
└── ou=grupos
    └── cn=suporte
```

---

## 2. Instalar

Entre como root (`su -` ou `sudo -i`).

### 2.1 Defina o nome do servidor

```bash
hostnamectl set-hostname ldap.sdtr.uniube.br
```

Confira que o nome resolve:

```bash
hostname -f
```

Se não resolver, adicione em `/etc/hosts`:

```text
127.0.1.1   ldap.sdtr.uniube.br ldap
```

### 2.2 Instale os pacotes

```bash
apt update
apt install -y dialog slapd ldap-utils
```

O `dialog` desenha as telas de pergunta. Durante a instalação, o Debian pede só a senha do administrador. Digite a mesma senha nas duas telas.

### 2.3 Responda as perguntas na tela

A instalação não pergunta o domínio. Ela usa o nome da máquina. Para escolher `sdtr.uniube.br`, rode:

```bash
dpkg-reconfigure slapd
```

Responda assim (use as setas, `Tab` e `Enter`):

| Pergunta | Resposta |
|---|---|
| Omit OpenLDAP server configuration? | No |
| DNS domain name | `sdtr.uniube.br` |
| Organization name | `SDTR` |
| Administrator password | sua senha (duas vezes) |
| Database backend to use | MDB |
| Do you want the database to be removed when slapd is purged? | No |
| Move old database? | Yes |

O domínio `sdtr.uniube.br` vira a base `dc=sdtr,dc=uniube,dc=br`.

Se as telas não aparecerem, force o modo de tela:

```bash
DEBIAN_FRONTEND=dialog dpkg-reconfigure slapd
```

Se o debconf pular as perguntas (respostas antigas guardadas), limpe e refaça:

```bash
echo PURGE | debconf-communicate slapd
dpkg-reconfigure slapd
```

> Modo automático, sem telas: veja o apêndice A no fim do tutorial.

### 2.4 Confira que o serviço roda

```bash
systemctl status slapd
ss -tlnp | grep slapd
```

Você deve ver o serviço `active (running)` e a porta `389` aberta.

---

## 3. Conferir a instalação

### 3.1 Versão

```bash
slapd -VV 2>&1 | head -3
```

### 3.2 Ver a base criada

Como root, o acesso local por socket (`ldapi:///`) não pede senha:

```bash
ldapsearch -Y EXTERNAL -H ldapi:/// -b "dc=sdtr,dc=uniube,dc=br" -LLL dn
```

Saída esperada:

```text
dn: dc=sdtr,dc=uniube,dc=br
```

### 3.3 Ver a configuração do servidor

```bash
ldapsearch -Y EXTERNAL -H ldapi:/// -b cn=config -LLL \
  "(olcDatabase={1}mdb)" olcSuffix olcRootDN
```

Saída esperada:

```text
dn: olcDatabase={1}mdb,cn=config
olcSuffix: dc=sdtr,dc=uniube,dc=br
olcRootDN: cn=admin,dc=sdtr,dc=uniube,dc=br
```

### 3.4 Configurar o cliente

Edite `/etc/ldap/ldap.conf`:

```text
BASE    dc=sdtr,dc=uniube,dc=br
URI     ldap://localhost
```

Agora teste com a senha do admin:

```bash
ldapwhoami -x -D "cn=admin,dc=sdtr,dc=uniube,dc=br" -W
```

Resposta esperada: `dn:cn=admin,dc=sdtr,dc=uniube,dc=br`

---

## 4. Criar os ramos: pessoas e grupos

Crie uma pasta de trabalho:

```bash
mkdir -p /root/ldif && cd /root/ldif
```

### 4.1 Arquivo `01-ramos.ldif`

```ldif
dn: ou=pessoas,dc=sdtr,dc=uniube,dc=br
objectClass: organizationalUnit
ou: pessoas

dn: ou=grupos,dc=sdtr,dc=uniube,dc=br
objectClass: organizationalUnit
ou: grupos
```

### 4.2 Carregar

```bash
ldapadd -x -D "cn=admin,dc=sdtr,dc=uniube,dc=br" -W -f 01-ramos.ldif
```

Saída esperada:

```text
adding new entry "ou=pessoas,dc=sdtr,dc=uniube,dc=br"
adding new entry "ou=grupos,dc=sdtr,dc=uniube,dc=br"
```

---

## 5. Adicionar informações

### 5.1 Gerar o hash da senha

Nunca grave senha em texto puro.

```bash
slappasswd -h {SSHA}
```

Digite a senha duas vezes. Copie a linha que começa com `{SSHA}`.

### 5.2 Adicionar pessoas

Abaixo está o conteúdo do arquivo de exemplo `02-pessoas.ldif`, que adiciona 2 entradas de usuário ao diretório. Crie um arquivo novo, copie um dos usuários para ele, substitua o nome seu usuário do Github e cole a senha que voce gerou no passo anterior como valor do atributo `userPassword`. Salve o arquivo `seu_id_github.ldif`:

```ldif
dn: uid=maria,ou=pessoas,dc=sdtr,dc=uniube,dc=br
objectClass: inetOrgPerson
objectClass: posixAccount
objectClass: shadowAccount
uid: maria
cn: Maria Silva
sn: Silva
givenName: Maria
mail: maria@sdtr.uniube.br
uidNumber: 10001
gidNumber: 10001
homeDirectory: /home/maria
loginShell: /bin/bash
userPassword: {SSHA}COLE_O_HASH_AQUI

dn: uid=joao,ou=pessoas,dc=sdtr,dc=uniube,dc=br
objectClass: inetOrgPerson
objectClass: posixAccount
objectClass: shadowAccount
uid: joao
cn: Joao Souza
sn: Souza
givenName: Joao
mail: joao@sdtr.uniube.br
uidNumber: 10002
gidNumber: 10002
homeDirectory: /home/joao
loginShell: /bin/bash
userPassword: {SSHA}COLE_O_HASH_AQUI
```

```bash
ldapadd -x -D "cn=admin,dc=sdtr,dc=uniube,dc=br" -W -f 02-pessoas.ldif
```

### 5.3 Adicionar um grupo

Um `groupOfNames` precisa de ao menos um `member`. Por isso criamos as pessoas antes.

Arquivo `03-grupos.ldif`:

```ldif
dn: cn=suporte,ou=grupos,dc=sdtr,dc=uniube,dc=br
objectClass: groupOfNames
cn: suporte
description: Equipe de suporte
member: uid=maria,ou=pessoas,dc=sdtr,dc=uniube,dc=br
```

```bash
ldapadd -x -D "cn=admin,dc=sdtr,dc=uniube,dc=br" -W -f 03-grupos.ldif
```

### 5.4 Consultar

Toda a árvore:

```bash
ldapsearch -x -D "cn=admin,dc=sdtr,dc=uniube,dc=br" -W -LLL
```

Só as pessoas, mostrando alguns campos:

```bash
ldapsearch -x -D "cn=admin,dc=sdtr,dc=uniube,dc=br" -W -LLL \
  -b "ou=pessoas,dc=sdtr,dc=uniube,dc=br" "(objectClass=inetOrgPerson)" uid cn mail
```

Buscar uma pessoa pelo nome:

```bash
ldapsearch -x -D "cn=admin,dc=sdtr,dc=uniube,dc=br" -W -LLL \
  -b "dc=sdtr,dc=uniube,dc=br" "(cn=Maria*)" dn mail
```

Ver os membros de um grupo:

```bash
ldapsearch -x -D "cn=admin,dc=sdtr,dc=uniube,dc=br" -W -LLL \
  -b "ou=grupos,dc=sdtr,dc=uniube,dc=br" "(cn=suporte)" member
```

---

## 6. Alterar informações

Use `ldapmodify`. Cada bloco tem um `changetype: modify` e uma ação:
`add`, `replace` ou `delete`. O traço `-` separa as ações.

### 6.1 Trocar o valor de um campo (`replace`)

Arquivo `10-trocar-mail.ldif`:

```ldif
dn: uid=maria,ou=pessoas,dc=sdtr,dc=uniube,dc=br
changetype: modify
replace: mail
mail: maria.silva@sdtr.uniube.br
```

```bash
ldapmodify -x -D "cn=admin,dc=sdtr,dc=uniube,dc=br" -W -f 10-trocar-mail.ldif
```

### 6.2 Acrescentar um campo (`add`)

Arquivo `11-add-telefone.ldif`:

```ldif
dn: uid=maria,ou=pessoas,dc=sdtr,dc=uniube,dc=br
changetype: modify
add: telephoneNumber
telephoneNumber: +55 34 3000-0000
```

```bash
ldapmodify -x -D "cn=admin,dc=sdtr,dc=uniube,dc=br" -W -f 11-add-telefone.ldif
```

### 6.3 Remover um campo (`delete`)

Arquivo `12-del-telefone.ldif`:

```ldif
dn: uid=maria,ou=pessoas,dc=sdtr,dc=uniube,dc=br
changetype: modify
delete: telephoneNumber
```

```bash
ldapmodify -x -D "cn=admin,dc=sdtr,dc=uniube,dc=br" -W -f 12-del-telefone.ldif
```

### 6.4 Várias mudanças de uma vez

```ldif
dn: uid=joao,ou=pessoas,dc=sdtr,dc=uniube,dc=br
changetype: modify
replace: loginShell
loginShell: /bin/zsh
-
replace: sn
sn: Souza Lima
```

### 6.5 Colocar alguém em um grupo

Arquivo `13-add-membro.ldif`:

```ldif
dn: cn=suporte,ou=grupos,dc=sdtr,dc=uniube,dc=br
changetype: modify
add: member
member: uid=joao,ou=pessoas,dc=sdtr,dc=uniube,dc=br
```

```bash
ldapmodify -x -D "cn=admin,dc=sdtr,dc=uniube,dc=br" -W -f 13-add-membro.ldif
```

### 6.6 Tirar alguém de um grupo

```ldif
dn: cn=suporte,ou=grupos,dc=sdtr,dc=uniube,dc=br
changetype: modify
delete: member
member: uid=joao,ou=pessoas,dc=sdtr,dc=uniube,dc=br
```

> O grupo não pode ficar sem nenhum `member`. Remover o último dá erro
> `object class violation`. Apague o grupo inteiro nesse caso.

### 6.7 Renomear uma entrada (`modrdn`)

Arquivo `14-renomear.ldif`:

```ldif
dn: uid=joao,ou=pessoas,dc=sdtr,dc=uniube,dc=br
changetype: modrdn
newrdn: uid=joao.souza
deleteoldrdn: 1
```

> Os grupos guardam o DN antigo. Atualize o `member` deles depois.

### 6.8 Trocar a senha de um usuário

Pelo admin:

```bash
ldappasswd -x -D "cn=admin,dc=sdtr,dc=uniube,dc=br" -W -S \
  "uid=maria,ou=pessoas,dc=sdtr,dc=uniube,dc=br"
```

Pelo próprio usuário:

```bash
ldappasswd -x -D "uid=maria,ou=pessoas,dc=sdtr,dc=uniube,dc=br" -W -S
```

---

## 7. Remover informações

> Remover é difícil de desfazer. Faça backup antes (seção 10).

### 7.1 Apagar uma entrada

```bash
ldapdelete -x -D "cn=admin,dc=sdtr,dc=uniube,dc=br" -W \
  "uid=joao,ou=pessoas,dc=sdtr,dc=uniube,dc=br"
```

### 7.2 Apagar um grupo

```bash
ldapdelete -x -D "cn=admin,dc=sdtr,dc=uniube,dc=br" -W \
  "cn=suporte,ou=grupos,dc=sdtr,dc=uniube,dc=br"
```

### 7.3 Apagar um ramo com tudo dentro

Sem `-r`, o `ldapdelete` recusa apagar ramo que tem filhos (`Operation not allowed on non-leaf`).

```bash
ldapdelete -x -D "cn=admin,dc=sdtr,dc=uniube,dc=br" -W -r \
  "ou=grupos,dc=sdtr,dc=uniube,dc=br"
```

### 7.4 Conferir

```bash
ldapsearch -x -D "cn=admin,dc=sdtr,dc=uniube,dc=br" -W -LLL -b "dc=sdtr,dc=uniube,dc=br" dn
```

---

## 8. Testar o login de um usuário

```bash
ldapwhoami -x -D "uid=maria,ou=pessoas,dc=sdtr,dc=uniube,dc=br" -W
```

Se der `dn:uid=maria,...`, a senha está certa.

---

## 9. Segurança básica

### 9.1 Trocar a senha do admin

```bash
slappasswd -h {SSHA}
```

Arquivo `20-senha-admin.ldif`:

```ldif
dn: olcDatabase={1}mdb,cn=config
changetype: modify
replace: olcRootPW
olcRootPW: {SSHA}COLE_O_HASH_AQUI
```

```bash
ldapmodify -Y EXTERNAL -H ldapi:/// -f 20-senha-admin.ldif
```

### 9.2 Índices para buscas rápidas

Arquivo `21-indices.ldif`:

```ldif
dn: olcDatabase={1}mdb,cn=config
changetype: modify
add: olcDbIndex
olcDbIndex: uid eq
-
add: olcDbIndex
olcDbIndex: mail eq
-
add: olcDbIndex
olcDbIndex: member eq
```

```bash
ldapmodify -Y EXTERNAL -H ldapi:/// -f 21-indices.ldif
```

### 9.3 Ver as regras de acesso (ACL) atuais

```bash
ldapsearch -Y EXTERNAL -H ldapi:/// -b cn=config -LLL \
  "(olcDatabase={1}mdb)" olcAccess
```

Por padrão no Debian:

- Só o dono e o admin leem ou trocam `userPassword`.
- Todos que fizeram login leem o resto.
- Sem login, ninguém lê nada, exceto fazer o bind.

### 9.4 Cifrar a conexão (TLS)

Sem TLS, a senha viaja em texto puro na rede. Para produção, use certificado.

Para um teste, crie um certificado próprio:

```bash
apt install -y gnutls-bin ssl-cert
mkdir -p /etc/ldap/tls && cd /etc/ldap/tls

openssl req -x509 -nodes -newkey rsa:4096 -days 365 \
  -keyout ldap.key -out ldap.crt \
  -subj "/CN=ldap.sdtr.uniube.br" \
  -addext "subjectAltName=DNS:ldap.sdtr.uniube.br"

chown openldap:openldap ldap.key ldap.crt
chmod 600 ldap.key
```

Arquivo `/root/ldif/30-tls.ldif`:

```ldif
dn: cn=config
changetype: modify
replace: olcTLSCertificateFile
olcTLSCertificateFile: /etc/ldap/tls/ldap.crt
-
replace: olcTLSCertificateKeyFile
olcTLSCertificateKeyFile: /etc/ldap/tls/ldap.key
```

```bash
ldapmodify -Y EXTERNAL -H ldapi:/// -f /root/ldif/30-tls.ldif
```

Ative `ldaps://` em `/etc/default/slapd`:

```text
SLAPD_SERVICES="ldap:/// ldapi:/// ldaps:///"
```

```bash
systemctl restart slapd
```

Teste (com certificado próprio, diga ao cliente para confiar nele):

```bash
LDAPTLS_CACERT=/etc/ldap/tls/ldap.crt \
  ldapwhoami -x -H ldaps://ldap.sdtr.uniube.br -D "cn=admin,dc=sdtr,dc=uniube,dc=br" -W
```

### 9.5 Firewall

Se usar `ufw`:

```bash
ufw allow 389/tcp
ufw allow 636/tcp
```

Libere só para as redes que precisam.

---

## 10. Backup e restauração

### 10.1 Backup

```bash
mkdir -p /root/backup
slapcat -n 0 -l /root/backup/config-$(date +%F).ldif
slapcat -n 1 -l /root/backup/dados-$(date +%F).ldif
```

- `-n 0` é a configuração (`cn=config`).
- `-n 1` é a base `dc=sdtr,dc=uniube,dc=br`.

### 10.2 Restaurar os dados

Pare o serviço. Guarde os dados atuais. Depois carregue o backup.

```bash
systemctl stop slapd
mv /var/lib/ldap /var/lib/ldap.old
mkdir /var/lib/ldap
slapadd -n 1 -l /root/backup/dados-AAAA-MM-DD.ldif
chown -R openldap:openldap /var/lib/ldap
systemctl start slapd
```

Desfazer: apague `/var/lib/ldap` e renomeie `/var/lib/ldap.old` de volta.

---

## 11. Problemas comuns

| Erro | Causa provável | O que fazer |
|---|---|---|
| `Invalid credentials (49)` | Senha ou DN errado. | Confira o DN completo do admin. |
| `No such object (32)` | O pai do DN não existe. | Crie o ramo antes. |
| `Already exists (68)` | A entrada já existe. | Use `ldapmodify` em vez de `ldapadd`. |
| `Insufficient access (50)` | Sem permissão (ACL). | Use o admin ou revise o `olcAccess`. |
| `Object class violation (65)` | Falta campo obrigatório. | Veja `must` do objectClass. Ex.: `sn` e `cn` em `inetOrgPerson`. |
| `Can't contact LDAP server (-1)` | Serviço parado ou porta fechada. | `systemctl status slapd` e `ss -tlnp`. |
| `Naming violation (64)` | O RDN não está nos atributos da entrada. | Ponha `uid: maria` se o RDN é `uid=maria`. |
| `Type or value exists (20)` | Valor repetido no `add`. | Use `replace`. |

Ver o log:

```bash
journalctl -u slapd -e
```

Para ver mais detalhes, ligue o log de conexões e buscas:

```ldif
dn: cn=config
changetype: modify
replace: olcLogLevel
olcLogLevel: stats
```

```bash
ldapmodify -Y EXTERNAL -H ldapi:/// -f /root/ldif/40-log.ldif
```

Volte para `none` quando terminar.

---

## 12. Resumo dos comandos

| Tarefa | Comando |
|---|---|
| Instalar | `apt install slapd ldap-utils` |
| Adicionar | `ldapadd -x -D "cn=admin,dc=sdtr,dc=uniube,dc=br" -W -f arquivo.ldif` |
| Buscar | `ldapsearch -x -D "cn=admin,dc=sdtr,dc=uniube,dc=br" -W -LLL -b "dc=sdtr,dc=uniube,dc=br" "(filtro)"` |
| Alterar | `ldapmodify -x -D "cn=admin,dc=sdtr,dc=uniube,dc=br" -W -f arquivo.ldif` |
| Remover | `ldapdelete -x -D "cn=admin,dc=sdtr,dc=uniube,dc=br" -W "DN"` |
| Trocar senha | `ldappasswd -x -D "cn=admin,dc=sdtr,dc=uniube,dc=br" -W -S "DN"` |
| Backup | `slapcat -n 1 -l dados.ldif` |
| Configuração | `ldapmodify -Y EXTERNAL -H ldapi:/// -f arquivo.ldif` |

## 13. Próximos passos

- Ligar o Debian ao LDAP para login de usuários (`sssd` ou `libnss-ldapd`).
- Ativar o overlay `memberOf` para ver os grupos de cada pessoa.
- Montar uma réplica (syncrepl) para alta disponibilidade.
- Usar uma interface web, como o phpLDAPadmin ou o LDAP Account Manager.

---

## Apêndice A: instalação automática (sem telas)

Use quando quiser repetir a instalação sem digitar nada. Troque `SenhaForte123` pela sua senha.

```bash
apt update
apt install -y debconf-utils

cat <<'EOF' | debconf-set-selections
slapd slapd/domain string sdtr.uniube.br
slapd shared/organization string SDTR
slapd slapd/password1 password SenhaForte123
slapd slapd/password2 password SenhaForte123
slapd slapd/backend select MDB
slapd slapd/purge_database boolean false
slapd slapd/move_old_database boolean true
slapd slapd/no_configuration boolean false
EOF

apt install -y slapd ldap-utils
dpkg-reconfigure -f noninteractive slapd
```

> Risco: a senha fica no histórico do shell e no cache do debconf.
> Troque-a depois (seção 9) e rode `history -c`.
