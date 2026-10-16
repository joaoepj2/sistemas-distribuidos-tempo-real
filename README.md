# sistemas-distribuidos-tempo-real
Site da disciplina de Sistemas Distribuídos e de Tempo Real

- [Tutoriais da turma](tutoriais/README.md)
- BIND 9: [duas máquinas](tutoriais/dns/bind9/README.md) ou [um computador](tutoriais/dns/bind9/laboratorio-local.md).

As diretrizes abaixo orientam a preparação e a entrega dos tutoriais.

# Diretrizes para Tutoriais de Middleware em Sistemas Distribuídos

Os tutoriais serão confeccionados dentro e fora da sala de aula. Sempre tragam os computadores para as aulas. Fiquem a vontade para perguntar e propor melhorias neste documento.

## Objetivo e entregáveis

Cada pessoa produz um tutorial reproduzível que permite a um colega instalar, configurar e demonstrar um middleware em sala, em cerca de 15 minutos.

O foco não é decorar comandos: é entender qual problema de sistemas distribuídos o software resolve (nomeação, diretório e autenticação, comunicação assíncrona) e mostrar isso funcionando.

Cada pessoa entrega:

- Um tutorial em Markdown, seguindo a estrutura obrigatória descrita abaixo.
- Um ambiente reprodutível em Docker Compose, que sobe com um único comando.
- Um roteiro de demonstração com tempo marcado e plano B.
- A demonstração ao vivo, com participação da turma.

## Escopo: temas, softwares

Cada pessoa escolhe um software de um dos três temas abaixo. Duas pessoas do mesmo tema devem escolher softwares diferentes, para a turma poder comparar as abordagens.

| Tema | Problema distribuído que resolve | Softwares sugeridos |
| --- | --- | --- |
| Diretório (LDAP) | Identidade e autenticação centralizadas | OpenLDAP, 389 Directory Server |
| Nomes (DNS) | Nomeação e descoberta de serviços | BIND 9, CoreDNS |
| Filas | Comunicação assíncrona e desacoplamento | Apache Kafka, RabbitMQ (AMQP) |
| etcd | Consenso e configuração compartilhada (Raft) | Cluster de 3 nós; derrubar o líder e mostrar a nova eleição |
| MinIO | Armazenamento de objetos compatível com S3, modo distribuído | Enviar um objeto e lê-lo com um disco ou nó fora do ar |
| gRPC | Chamada remota de procedimento entre serviços | Cliente e servidor em linguagens diferentes, com um contrato `.proto` |
| NATS | Mensageria leve (publicação e assinatura) | Um publicador e vários assinantes; mostrar entrega com e sem JetStream |
| Redpanda | Log distribuído compatível com a API do Kafka | O mesmo teste do Kafka, comparando a facilidade de instalação |
| Apache Pulsar, ActiveMQ Artemis | Mensageria com outros modelos de armazenamento e de AMQP | Fila durável com consumidor que cai e volta |

AMQP é um protocolo, não um software. Quem escolher esse tema deve nomear a implementação usada (RabbitMQ é a mais comum) e dizer o que seria diferente em outra.

Todos as pessoas precisam aparecer no histórico de commits do repositório.

## Princípios de um bom tutorial

Um bom tutorial pode ser seguido por outra pessoa, do zero, sem pedir ajuda ao autor. Seis princípios orientam isso:

1. **Reprodutível.** Quem segue os passos em uma máquina limpa chega ao mesmo resultado.
2. **Explica o porquê.** Cada comando ou arquivo de configuração diz o que faz e que problema resolve.
3. **Verificável.** Cada etapa termina com um comando de teste e a saída esperada.
4. **Distribuído de verdade.** Subir um único serviço não basta: a demonstração usa pelo menos dois clientes ou dois nós e provoca uma falha.
5. **Honesto.** Registra os erros reais encontrados e como foram os resolvidos.
6. **Enxuto.** Só o necessário para o objetivo. Opções avançadas vão para a seção de referências.

## Estrutura obrigatória do tutorial

O tutorial segue esta ordem de seções, para facilitar a revisão e a comparação entre diferentes:

1. **Visão geral.** Que problema o software resolve, onde ele entra em um sistema distribuído, quais as alternativas e quando não usá-lo. Inclua um diagrama simples da arquitetura da demonstração.
2. **Conceitos mínimos.** Glossário de 5 a 8 termos que o leitor precisa para entender o resto (por exemplo: entrada, DN e base no LDAP; zona, registro e resolvedor no DNS; tópico, partição e offset no Kafka; exchange, binding e fila no AMQP).
3. **Pré-requisitos.** Sistema operacional, versões, portas usadas, memória e disco necessários.
4. **Instalação.** Via Docker Compose (obrigatório). Instalação nativa por pacote é opcional.
5. **Configuração.** Arquivos comentados, explicando o que mudar e por quê. Nada de "copie e cole" sem explicação.
6. **Demonstração.** O roteiro completo, descrito na seção de demonstração em sala.
7. **Verificação e teste de falhas.** Como confirmar que funciona e o que acontece quando algo cai.
8. **Problemas comuns.** Erros reais, sintomas e correções.
9. **Limpeza.** Como derrubar tudo e apagar volumes, deixando a máquina como estava.
10. **Referências.** Documentação oficial, com a versão consultada.

## Ambiente reprodutível

O ambiente inteiro deve subir com `docker compose up -d` a partir da pasta do tutorial. Regras:

- **Versões fixas.** Use tags de imagem explícitas, nunca `latest`, e registre a data em que o tutorial foi testado.
- **Portas documentadas.** Liste em uma tabela todas as portas expostas. Portas privilegiadas (53 do DNS, 389 do LDAP) exigem cuidado: mapeie para portas altas, como 1053 e 1389, para evitar conflito com serviços da máquina e a necessidade de root.
- **Rede própria.** Declare uma rede Docker dedicada, para que os contêineres se encontrem pelo nome.
- **Dados em volumes nomeados.** Inclua o comando que reinicia o ambiente do zero.
- **Sem segredos reais.** Senhas de laboratório ficam em um arquivo `.env.example` versionado.
- **Mais de um nó.** Quando o software suportar, o Compose sobe pelo menos dois (réplicas LDAP, DNS primário e secundário, brokers ou consumidores múltiplos).
- **Memória informada.** Diga quanto o ambiente consome. Kafka e 389 Directory Server são os mais pesados do conjunto.
- **Teste em máquina limpa.** Antes de entregar, outra pessoa executa o tutorial do zero para validar. Linux é a referência; avise o que muda em Windows e macOS.

## Demonstração em sala

A demonstração dura 15 minutos, mais 5 de perguntas, e segue três atos:

1. **Subir (3 min).** Mostre o `docker compose up` e a verificação de que os serviços estão saudáveis. Se a subida for lenta, comece com o ambiente já iniciado e mostre só os logs.
2. **Funcionar (7 min).** O fluxo normal, com a turma participando. Exemplos: um colega consulta o DNS de outro a partir do próprio notebook, faz login no LDAP, ou publica uma mensagem na fila.
3. **Falhar (5 min).** Derrube um nó, um consumidor ou altere um dado, e mostre o que o sistema faz. É aqui que o conceito de sistemas distribuídos aparece.

Fechamento obrigatório: uma frase ligando o que foi visto a um conceito da disciplina (replicação, consistência, cache, desacoplamento, disponibilidade).

Plano B, preparado antes da aula:

- Imagens Docker já baixadas na máquina. Nunca dependa da rede da sala.
- Ambiente pré-iniciado em uma segunda janela.
- Gravação da demonstração em vídeo ou terminal (por exemplo, com asciinema) para o pior caso.

O roteiro vai em um arquivo `roteiro-demo.md`, com cada comando, a saída esperada e o tempo previsto.

## O que demonstrar em cada tecnologia

O mínimo abaixo vale para qualquer software do tema. Quem quiser ir além fique a vontade.

### LDAP (OpenLDAP, 389 Directory Server)

- **Configurar:** uma base (por exemplo, `dc=sdtr,dc=com`), unidades organizacionais, ao menos 3 usuários e 2 grupos, e uma regra de controle de acesso simples.
- **Demonstrar:** consulta com `ldapsearch`, inclusão com `ldapadd`, autenticação (bind) de um usuário e de um usuário com senha errada. Mostre um cliente real usando o diretório, como login em uma aplicação ou via SSSD.
- **Provocar falha:** com replicação entre dois nós (syncrepl no OpenLDAP, replicação multi-supplier no 389 DS), derrube o primeiro e autentique no segundo.
- **Conceito:** replicação, consistência eventual, ponto único de falha.

### DNS (BIND 9, CoreDNS)

- **Configurar:** uma zona própria (por exemplo, `lab.local`) com registros A, CNAME e SRV, e encaminhamento (forwarder) para resolver nomes externos. No BIND, uma zona primária e uma secundária. No CoreDNS, um `Corefile` com os plugins `file`, `forward` e `cache`.
- **Demonstrar:** consultas com `dig`, a diferença entre resposta autoritativa e em cache, e a resolução a partir do notebook de um colega.
- **Provocar falha ou variação:** altere um registro e observe o efeito do TTL. No BIND, derrube o primário e mostre o secundário respondendo.
- **Conceito:** nomeação hierárquica, cache e TTL, replicação de zona.

### Filas (Kafka, AMQP/RabbitMQ)

- **Configurar:** Kafka com um broker em modo KRaft, um tópico com partições e um grupo de consumidores. RabbitMQ com exchange, binding e fila durável, testando ao menos os tipos `direct` e `topic`.
- **Demonstrar:** um produtor e vários consumidores. Mostre o desacoplamento: um consumidor desligado recebe as mensagens quando volta. No Kafka, releia mensagens pelo offset. No RabbitMQ, mostre confirmação (ack) e reentrega.
- **Provocar falha:** derrube um consumidor no meio do processamento e mostre o que acontece com a mensagem. Se o ambiente suportar, derrube também um broker.
- **Conceito:** desacoplamento no tempo, garantias de entrega, ordenação por partição, escalabilidade horizontal.

## Outros middlewares possíveis

Quem preferir um tema fora dos três principais podem escolher um software desta lista, combinando antes com o professor. As mesmas regras de ambiente, demonstração e entrega se aplicam. Para iniciantes, os mais leves de subir são etcd, Consul, Redis/Valkey, HAProxy e NATS; Kafka, Cassandra e Kubernetes consomem muita memória e deixam a demonstração mais arriscada.

| Software | Problema que resolve | Demonstração mínima |
| --- | --- | --- |
| Apache ZooKeeper | Coordenação, locks e eleição de líder | Dois clientes disputando um lock; derrubar o detentor |
| Consul | Descoberta de serviços e health checks | Registrar um serviço, consultá-lo por DNS e vê-lo sair quando o health check falha |
| Mosquitto, EMQX (MQTT) | Publicação e assinatura para IoT | Os três níveis de QoS e uma mensagem retida |
| Keycloak | Login único (OIDC, SAML) | Um aplicativo autenticando via Keycloak, de preferência federado ao LDAP de outra pessoa |
| FreeIPA | LDAP, Kerberos e DNS integrados | Cadastrar um usuário e usá-lo para autenticar em outra máquina |
| PowerDNS, Unbound | DNS autoritativo com banco de dados e resolvedor recursivo | Zona servida a partir do banco; comparar resolução recursiva com a do BIND |
| Redis ou Valkey, Memcached | Cache e replicação em memória | Réplica sincronizada; no Redis, failover com Sentinel |
| Cassandra | Banco distribuído com consistência ajustável | Escrita e leitura com níveis de consistência diferentes, com um nó fora do ar (teorema CAP) |
| MongoDB, PostgreSQL | Replicação de banco e failover | Eleição de um novo primário depois de derrubar o atual |
| HAProxy, Nginx, Envoy | Balanceamento de carga | Tráfego se redistribuindo quando um servidor falha no health check |
| Prometheus e Grafana, OpenTelemetry e Jaeger | Métricas e rastreamento distribuído | Monitorar os serviços de outra pessoa e rastrear uma requisição entre dois serviços |
| chrony (NTP) | Sincronização de relógios | Provocar um desvio de relógio e observar a correção |
| Kubernetes (kind ou minikube), Docker Swarm | Orquestração de contêineres | Derrubar uma réplica e ver o reagendamento automático |

## Formato e entrega via GitHub

O tutorial é entregue por pull request no repositório da disciplina, com esta estrutura de pastas:

```
tutoriais/<tema>/<software>/
├── README.md          # o tutorial, na ordem da estrutura obrigatória
├── docker-compose.yml
├── .env.example
├── roteiro-demo.md    # passo a passo da demonstração, com tempos
└── imagens/           # diagramas e capturas de tela
```

Fluxo de trabalho:

1. **Issue.** Cada pessoa manifesta interesse por uma issue existente ou abre uma issue "Tutorial: \<software>" para reservar o tema e evitar duplicidade.
2. **Fork e branch.** Cada pessoa trabalha em um fork, em uma branch própria.
3. **Commits pequenos.** Cada pessoa contribui com commits identificáveis.
4. **Pull request.** Aberto com o checklist final preenchido.
5. **Revisão cruzada.** Outra pessoa executa o tutorial do zero e comenta o que não funcionou ou ficou confuso. O autor corrige antes da apresentação.
6. **Apresentação.** Só depois da revisão cruzada, com o pull request aprovado.

## Rubrica de avaliação

Sugestão de pesos, somando 100 pontos; ajuste conforme a sua disciplina.

| Critério | Peso | O que se espera de um trabalho excelente |
| --- | --- | --- |
| Reprodutibilidade | 25 | Outra pessoa executa do zero, sem ajuda, e obtém o resultado descrito |
| Corretude técnica e configuração | 20 | Configuração funcional, comentada e justificada; versões fixas |
| Demonstração em sala | 20 | Dentro do tempo, com participação da turma e plano B pronto |
| Comportamento distribuído e falhas | 15 | Pelo menos dois nós ou clientes e uma falha provocada e explicada |
| Clareza didática | 10 | Conceitos explicados, diagramas úteis, problemas comuns documentados |
| Colaboração no GitHub | 10 | Issue, commits de todos, pull request e revisão cruzada feitos |

## Checklist antes de entregar

- [ ] O tutorial segue as 10 seções da estrutura obrigatória
- [ ] `docker compose up -d` sobe o ambiente em máquina limpa, com versões fixas
- [ ] Todas as portas e requisitos de memória estão documentados
- [ ] Cada etapa tem comando de verificação e saída esperada
- [ ] A demonstração usa pelo menos dois nós ou clientes e provoca uma falha
- [ ] O roteiro de demonstração cabe em 15 minutos e tem plano B
- [ ] Outra pessoa executou o tutorial e as correções foram feitas
- [ ] Deve haver commits toda semana no repositório
- [ ] A seção de limpeza remove contêineres, redes e volumes

