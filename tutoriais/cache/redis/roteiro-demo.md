# Roteiro da demonstração: Redis + Sentinel (15 min + 5 de perguntas)

Tutorial completo: [README.md](README.md)

## Antes da aula (checklist)

- [ ] `docker compose pull` feito em casa. A imagem precisa estar no notebook, para não depender da rede da sala
- [ ] `cp .env.example .env` feito
- [ ] Ensaio completo com `docker compose down -v && docker compose up -d`
- [ ] Ambiente **já iniciado** em uma segunda janela de terminal (plano B do ato 1)
- [ ] Gravação de tela da demonstração inteira, com OBS ou `asciinema rec`, para o pior caso
- [ ] IP do notebook anotado (`ip addr` / `ipconfig`) e escrito no quadro para os colegas
- [ ] Três terminais abertos na pasta `tutoriais/cache/redis`: **T1** (comandos), **T2** (contador) e **T3** (logs)
- [ ] Fonte do terminal grande o bastante para a sala ler

---

## Ato 1: Subir (3 min), de 0:00 a 3:00

| Tempo | Fala / ação | Comando (T1) | Saída esperada |
| --- | --- | --- | --- |
| 0:00 | "Redis é um banco em memória. Hoje: o que acontece quando o servidor cai?" | (mostrar o diagrama do README) | |
| 0:45 | Subir o ambiente | `docker compose up -d` | 6 linhas `Started` ou `Healthy` |
| 1:30 | Conferir a saúde | `docker compose ps` | 6 contêineres `(healthy)` |
| 2:15 | "Quem manda agora?" | `docker compose exec sentinel1 redis-cli -p 26379 SENTINEL get-master-addr-by-name mymaster` | `redis-primario` / `6379` |

**Plano B:** se o `up` demorar mais de 1 minuto, vá para a janela com o ambiente pré-iniciado e mostre só `docker compose ps`.

---

## Ato 2: Funcionar (7 min), de 3:00 a 10:00

| Tempo | Fala / ação | Comando (T1) | Saída esperada |
| --- | --- | --- | --- |
| 3:00 | Escrever no primário | `docker compose exec redis-primario redis-cli -a sdtr-lab-2026 --no-auth-warning SET aula:tema "Redis Sentinel"` | `OK` |
| 3:45 | Ler na réplica: "o dado foi copiado sozinho" | `docker compose exec redis-replica1 redis-cli -a sdtr-lab-2026 --no-auth-warning GET aula:tema` | `"Redis Sentinel"` |
| 4:30 | Tentar escrever na réplica | `docker compose exec redis-replica1 redis-cli -a sdtr-lab-2026 --no-auth-warning SET x 1` | `READONLY You can't write against a read only replica.` |
| 5:15 | Mostrar as réplicas em dia | `docker compose exec redis-primario redis-cli -a sdtr-lab-2026 --no-auth-warning INFO replication` | `connected_slaves:2`, os dois com `state=online` |
| 6:00 | **Turma participa:** cada colega escreve o próprio nome no primário e lê na réplica | No notebook do colega: `docker run --rm redis:7.4.2-alpine redis-cli -h <IP> -p 6380 -a sdtr-lab-2026 SET colega:<nome> presente` e depois `... -p 6381 ... GET colega:<nome>` | `OK`, depois `"presente"` |
| 8:30 | Contar quantos colegas escreveram | `docker compose exec redis-replica2 redis-cli -a sdtr-lab-2026 --no-auth-warning --scan --pattern 'colega:*'` | lista de nomes |
| 9:15 | Mostrar os Sentinels | `docker compose exec sentinel1 redis-cli -p 26379 SENTINEL master mymaster` | `num-slaves 2`, `num-other-sentinels 2`, `quorum 2` |

**Plano B da participação:** se a rede da sala bloquear o acesso entre notebooks, peça a um colega que dite o nome e execute o `SET` você mesma.

---

## Ato 3: Falhar (5 min), de 10:00 a 15:00

| Tempo | Fala / ação | Comando | Saída esperada |
| --- | --- | --- | --- |
| 10:00 | Iniciar o cliente que escreve a cada segundo | **T2:** `docker compose exec sentinel1 sh /demo/contador.sh` | `primário=redis-primario contador=1, 2, 3...` |
| 10:20 | Abrir os logs dos Sentinels | **T3:** `docker compose logs -f sentinel1 sentinel2 sentinel3` | |
| 10:40 | **Derrubar o primário** | **T1:** `docker compose stop redis-primario` | |
| 10:45 | Narrar o T2: "as escritas estão falhando" | (olhar o T2) | `ERRO: Could not connect...` por cerca de 7 s |
| 10:50 | Narrar o T3: "um suspeita, dois concordam, votam e escolhem" | (olhar o T3) | `+sdown`, `+odown #quorum 2/2`, `+elected-leader`, `+switch-master` |
| 11:00 | "O cliente achou o novo primário sozinho, e o contador **não voltou para zero**" | (olhar o T2) | `primário=redis-replica1` (ou `2`) e o contador continuando |
| 12:00 | Religar o antigo primário | **T1:** `docker compose start redis-primario` | |
| 12:15 | "Ele volta achando que ainda é o chefe..." | **T1:** `docker compose exec redis-primario redis-cli -a sdtr-lab-2026 --no-auth-warning ROLE` | `master` nos primeiros cerca de 10 s |
| 12:45 | "...e o Sentinel o rebaixa" | Repetir o `ROLE` | `slave` e o nome do novo primário. No T3: `+convert-to-slave` |
| 13:30 | Explicar o *split-brain*: por cerca de 10 s havia dois "primários" | | |
| 14:15 | **Fechamento** (frase abaixo) | `Ctrl+C` no T2 | |

**Fechamento obrigatório (dizer em voz alta):**

> "Replicar os dados não basta para ter disponibilidade: é preciso que um grupo de processos chegue a um acordo, por maioria, sobre quem manda. Esse acordo custa alguns segundos de indisponibilidade e, durante o split-brain, pode custar consistência."

**Plano B do ato 3:** se o failover não acontecer em 20 s, mostre a gravação a partir do momento da queda. A causa mais provável é um Sentinel fora do ar; confira com `docker compose ps`.

---

## Perguntas prováveis (5 min)

| Pergunta | Resposta curta |
| --- | --- |
| Por que 3 Sentinels e não 2? | Com 2, se um cair, o outro sozinho não tem maioria e nenhum failover acontece. Com 3, tolera-se 1 fora |
| Alguma escrita se perde? | Pode se perder. A replicação é assíncrona: uma escrita confirmada pelo primário que ainda não chegou à réplica se perde se ele cair nesse instante |
| Qual a diferença para o Redis Cluster? | O Sentinel dá **disponibilidade** a um conjunto de dados. O Cluster **divide** os dados entre vários primários para escalar |
| Por que não usar Redis como banco principal? | Os dados ficam em memória e a replicação é assíncrona. Serve para cache, sessão e contadores; não para pedidos ou dinheiro |

## Depois da aula

```bash
docker compose down -v
```
