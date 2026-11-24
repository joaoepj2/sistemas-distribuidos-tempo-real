# *LDAP*: o diretório do mundo distribuído

O que é, por que surgiu e qual o seu papel na construção de sistemas distribuídos modernos. Aula teórica — complementa os experimentos com OpenLDAP 2.6.

01 · O problema

## Quem é você, e quem pode fazer o quê — em vinte máquinas?

Em um sistema com uma única máquina, a identidade mora em um arquivo: `/etc/passwd`. Quando as máquinas passam a ser dez, vinte, mil, três problemas aparecem ao mesmo tempo:

- **Identidade duplicada:** o usuário `ana` existe em cada máquina, com senhas que divergem.
- **Administração que não escala:** demitir alguém significa visitar todas as máquinas.
- **Descoberta:** como um serviço novo descobre quem são os usuários, os grupos, as impressoras, os servidores de e-mail?

A resposta é um **serviço de diretório**: uma base compartilhada, consultável pela rede, otimizada para responder “quem/o quê tem estes atributos?”. O LDAP é o protocolo que se tornou o padrão para falar com esses diretórios.

02 · História

## Por que o LDAP surgiu

**anos 1970–80 · arquivos locais.** Cada máquina com seu `/etc/passwd` e `/etc/hosts`, copiados à mão.

**1985 · NIS (Yellow Pages, Sun).** Primeira centralização popular no Unix. Mapas planos, sem hierarquia, segurança fraca, dependente de difusão na rede local.

**1988 · X.500 (ITU-T/ISO).** Um diretório global e hierárquico, riquíssimo — mas acessado pelo protocolo **DAP** sobre a pilha OSI completa, pesada demais para os PCs e para o TCP/IP que dominava a prática.

**1993 · LDAP (Universidade de Michigan, RFC 1487).** Tim Howes e colegas criam um acesso *leve* (“Lightweight”) ao X.500: direto sobre TCP/IP, com operações simplificadas e valores representados como texto.

**1995–97 · LDAPv2 e LDAPv3 (RFC 1777, RFC 2251).** O v3 traz extensibilidade, SASL para autenticação, referências (*referrals*), UTF-8 e esquema consultável. O servidor deixa de ser só “porta de entrada” do X.500 e passa a ser um diretório por si só.

**1998 · OpenLDAP.** O código da Michigan vira projeto livre; os produtos comerciais (Netscape, Sun, IBM) aparecem.

**2000 · Active Directory.** A Microsoft constrói o login corporativo do Windows sobre LDAP + Kerberos + DNS. O LDAP vira infraestrutura onipresente.

**2006 · RFC 4510–4519.** Consolidação da especificação atual (o roteiro está na RFC 4510).

**hoje.** OIDC, SAML e SCIM dominam o login em aplicações web, mas muitos deles *consultam um diretório LDAP* por baixo.

|  | X.500 / DAP | LDAP |
| --- | --- | --- |
| **Transporte** | pilha OSI completa | TCP/IP direto (porta 389; 636 com TLS) |
| **Operações** | dezenas, com semânticas complexas | poucas: bind, search, add, modify, delete… |
| **Representação** | estruturas ASN.1 complexas | valores como cadeias de texto |
| **Alcance** | diretório global único | servidores independentes, federáveis |

**Ideia central:** o LDAP venceu não por ser o mais poderoso, mas por ser o mais *simples de implementar* sobre a rede que as pessoas realmente tinham.

03 · O modelo

## O que é, de fato, um diretório LDAP

“LDAP” nomeia o **protocolo**; o **diretório** é a base de dados; o **servidor** (OpenLDAP, 389 DS, Active Directory) é o software. O padrão define quatro modelos:

informação

#### Entradas e atributos

Cada entrada é um conjunto de atributos (`cn`, `mail`…). Os `objectClass` dizem quais atributos são obrigatórios ou permitidos — o **esquema**.

nomes

#### Árvore (DIT)

As entradas formam uma hierarquia. O nome único de cada uma é o **DN**, formado pelos **RDN**s do caminho até a raiz.

funcional

#### Operações

Autenticar (bind), buscar (search), comparar, incluir, alterar, renomear e remover entradas.

segurança

#### Autenticação e ACLs

Bind simples ou SASL, StartTLS para cifrar, e listas de controle de acesso por entrada e atributo.

### Explore a árvore (clique em um nó)

- - - 
  - - 
  - - 

```
← escolha uma entrada
```

Note que a árvore reflete a **organização**, não o armazenamento: poderia ser por departamento, por região ou por empresa. É isso que torna o espaço de nomes delegável.

04 · O protocolo

## Como cliente e servidor conversam

Uma sessão é uma conexão TCP com mensagens numeradas (`messageID`), codificadas em BER/ASN.1. Várias requisições podem estar em andamento na mesma conexão.

```
Cliente                                   Servidor (slapd :389)
  │── BindRequest(dn, credencial) ───────────▶│  autentica
  │◀──────────── BindResponse(success) ───────│
  │── SearchRequest(base, escopo, filtro) ───▶│  busca
  │◀──────── SearchResultEntry  (× N) ────────│
  │◀──────── SearchResultDone ────────────────│
  │── ModifyRequest(dn, alterações) ─────────▶│  altera (se a ACL permitir)
  │◀──────────── ModifyResponse ──────────────│
  │── UnbindRequest ─────────────────────────▶│  encerra
```

A operação central é a **busca**, definida por três parâmetros:

- **Base:** onde começar na árvore (`ou=pessoas,dc=sdtr,dc=uniube`).
- **Escopo:** só a base, um nível abaixo, ou toda a subárvore.
- **Filtro:** a condição, em notação prefixa: `(&(objectClass=inetOrgPerson)(|(uid=ana)(mail=*@sdtr.uniube)))`.

**Cuidado:** sem TLS, a senha do bind viaja em texto claro. E filtros montados concatenando texto do usuário sofrem **injeção de LDAP**, como o SQL injection.

05 · Comparando

## Diretório não é banco de dados relacional

|  | Diretório LDAP | Banco relacional |
| --- | --- | --- |
| **Padrão de uso** | muitíssimas leituras, poucas escritas | leituras e escritas misturadas |
| **Estrutura** | árvore hierárquica de entradas | tabelas e relações |
| **Consulta** | base + escopo + filtro por atributos | SQL com junções |
| **Transações** | atômica por entrada; sem transação entre entradas | ACID completo |
| **Replicação** | nativa, centrada em consistência eventual | varia (primária/réplica, consenso) |
| **Esquema** | padronizado e compartilhado entre produtos | definido por cada aplicação |

O diretório abre mão de transações amplas e de junções para ser **rápido na leitura, fácil de replicar e padronizado**. Essa troca é a chave para entender onde ele brilha.

06 · Importância

## O que o LDAP resolve em sistemas distribuídos

identidade

#### Fonte única da verdade

Um cadastro por pessoa, consultado por todos os serviços. Desativar uma conta tem efeito imediato em todo o sistema.

autenticação e autorização

#### Login único e grupos

Serviços fazem *bind* para validar a senha e consultam grupos para decidir permissões, sem guardar usuários próprios.

nomeação

#### Busca por atributos

Enquanto o DNS resolve *nome → endereço*, o diretório responde “quais entradas têm estes atributos?”: nomeação baseada em atributos.

disponibilidade

#### Replicação

Réplicas de leitura espalhadas pelos sites reduzem a latência e sobrevivem à queda de um nó. O OpenLDAP usa *syncrepl* (RFC 4533), inclusive com vários provedores de escrita.

escala

#### Delegação hierárquica

Subárvores podem morar em servidores diferentes, ligadas por *referrals* — a mesma ideia de delegação do DNS.

integração

#### Padrão aberto

Linux (PAM/SSSD), Wi-Fi 802.1X, VPN, e-mail, Git, Jenkins e Active Directory falam LDAP. Trocar o produto não obriga a trocar os clientes.

### O que a teoria de sistemas distribuídos enxerga aqui

- **Transparência de localização:** o cliente pede “a Ana”, não “a máquina onde a Ana está cadastrada”.
- **Consistência eventual, por escolha:** aceitar que uma réplica atrasada devolva dado antigo por alguns segundos compra disponibilidade. Para identidade, o custo costuma valer — exceto em revogação de acesso, onde o atraso é um risco a tratar.
- **Ponto único de falha:** um diretório centralizado é o “coração” da segurança. Se cair, ninguém entra. Por isso a réplica não é luxo, é requisito.
- **Desacoplamento:** as aplicações deixam de implementar cadastro e senha; dependem de uma interface estável.

07 · Hoje

## Onde o LDAP está, e onde não está mais

Em aplicações web modernas, o login costuma usar **OIDC** ou **SAML** por meio de um provedor de identidade (Keycloak, Entra ID, Okta). Esses provedores, porém, muitas vezes **federam um diretório LDAP/Active Directory** como origem dos usuários, e o **SCIM** sincroniza contas entre serviços. O LDAP deixou de ser a face visível do login, mas segue sendo o alicerce de muita infraestrutura.

| Continua forte | Limitações |
| --- | --- |
| Login em Linux, VPN e Wi-Fi corporativo; Active Directory e FreeIPA; catálogo de usuários e grupos para dezenas de serviços internos | Esquema rígido; sem transações entre entradas; ergonomia de API datada (sem REST/JSON); exige TLS e cuidado com ACLs; não serve para tokens de sessão curtos nem para o login em navegador sem um intermediário |

08 · Para pensar

## Perguntas de discussão

1\. Por que o LDAP aceita consistência eventual, mas um banco bancário não?

A frequência e o custo do erro são diferentes. Uma réplica de diretório atrasada raramente causa dano; um saldo errado causa. O projeto casa o modelo de consistência com o custo da inconsistência.

2\. DNS e LDAP são hierárquicos e replicados. Onde diferem?

O DNS mapeia um *nome* a um valor, com cache controlado por TTL. O LDAP guarda entradas ricas, consultáveis por atributos, com autenticação e controle de acesso por entrada.

3\. O que acontece se o único servidor LDAP cair?

Logins novos falham, mas sessões já abertas e caches locais (SSSD) podem sustentar o serviço por algum tempo. A solução é replicar e distribuir os servidores — como no experimento de falha da disciplina.

4\. Um funcionário é desligado. Quanto tempo leva para o acesso ser revogado?

Depende do atraso de replicação e da validade dos caches e tokens emitidos. É um bom exemplo de que consistência eventual tem consequências de segurança.

Referências

## Para aprofundar

- RFC 4510 — roteiro técnico do LDAP; RFC 4511 (protocolo), 4512 (modelo de informação), 4513 (autenticação e TLS), 4515 (filtros).
- RFC 2849 — formato LDIF. RFC 4533 — sincronização de réplicas (syncrepl).
- Tanenbaum & van Steen, *Distributed Systems* — capítulo sobre nomeação, que trata de serviços de diretório e nomeação baseada em atributos.
- Documentação do OpenLDAP 2.6 (*Administrator’s Guide*).

Aula teórica de LDAP · Sistemas Distribuídos e de Tempo Real
