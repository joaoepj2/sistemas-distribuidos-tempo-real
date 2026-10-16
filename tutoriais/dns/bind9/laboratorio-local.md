# BIND 9 em um computador

Este cenário usa dois contêineres com IPs e volumes próprios. Demonstra
transferência de zona e falha de serviço; ambos dependem do mesmo computador.
Para falha de VM/host, use o [tutorial em máquinas distintas](README.md).

## Preparação

Instale Docker e Compose >= 2.20. No Windows, use Docker Desktop com contêineres
Linux e backend WSL 2. Confira `docker version`, `docker compose version` e
`wsl --list --verbose`. Para usar Ubuntu, habilite sua integração no Docker
Desktop e acesse o mesmo clone por `/mnt/<unidade>/...`, sem instalar outro Engine.

Entre em `tutoriais/dns/bind9`. Use somente `compose.local.yml`, sem combinar
com o Compose do modo entre máquinas. Mantenha `-p bind9-local` em todos os comandos.

| Servidor | IP interno Docker | Porta interna UDP/TCP | Publicação no host UDP/TCP |
| --- | --- | --- | --- |
| Primário | 172.30.53.10 | 53 | 127.0.0.1:1053 |
| Secundário | 172.30.53.11 | 53 | 127.0.0.1:2053 |

Os padrões funcionam sem criar `.env`. Para mudar subnet, IPs ou portas, copie
o [modelo local da raiz](../../../.env.local.example) para `.env.local` nesta pasta:

```sh
cp ../../../.env.local.example .env.local
```

No PowerShell, use `Copy-Item ../../../.env.local.example .env.local`. O modelo
já tem os valores padrão: altere os campos `LOCAL_DNS_*` apenas se necessário.
Acrescente `--env-file .env.local` a **todos** os comandos Compose para usar esse
arquivo. Preserve um `.env.local` existente antes de substituí-lo.
Ao mudar a subnet, ajuste os dois IPs internos;
evite sobreposição com redes existentes. O `.env` do modo LAN não configura este modo.

## Iniciar e consultar

```sh
docker compose -p bind9-local -f compose.local.yml --profile ferramentas config --quiet
docker compose -p bind9-local -f compose.local.yml --profile ferramentas pull
docker compose -p bind9-local -f compose.local.yml up -d --wait --wait-timeout 120
docker compose -p bind9-local -f compose.local.yml ps -a
docker compose -p bind9-local -f compose.local.yml run --rm --no-deps cliente sh /testes/verificar.sh normal
docker compose -p bind9-local -f compose.local.yml logs --tail=30 dns-secundario
```

Esperam-se dois BIND saudáveis, dois configuradores finalizados com código zero
e teste aprovado. A zona é transferida com TSIG; o secundário não monta a zona
do primário. Cada BIND tem três volumes: configuração, cache e dados.

O teste interno verifica os [registros do exercício](README.md#7-verificação-e-teste-de-falhas).
`app.lab.test → 192.0.2.80` é uma resposta fictícia, independente da sua rede,
e não um site acessível. O healthcheck sozinho não comprova recebimento da zona.

Para testar as **portas publicadas pelo Windows**, execute no PowerShell:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File ./testes/testar-publicacao.ps1
```

Esperam-se quatro linhas `OK`: UDP/TCP em cada porta. Se mudou as portas, use
`-PortaPrimario <porta> -PortaSecundario <porta>`. A política de execução é aplicada
somente a esse processo. O script não altera o DNS padrão do Windows.
`nslookup` em portas alternativas falhou no Windows testado; use esse teste
ou `dig`. `Resolve-DnsName` não permite selecionar outra porta.

No Linux/macOS com `dig`, consulte `dig @127.0.0.1 -p 1053 app.lab.test A` e repita
com `-p 2053` e `+tcp`. Consultas internas, sozinhas, não comprovam a publicação no host.

## Outros contêineres e acesso externo

Um serviço na mesma rede Compose pode usar os dois DNS:

```yaml
# Trecho a adicionar ao serviço consumidor no mesmo projeto.
networks: [laboratorio]
dns:
  - ${LOCAL_DNS_PRIMARY_IP:-172.30.53.10}
  - ${LOCAL_DNS_SECONDARY_IP:-172.30.53.11}
```

O cliente já recebe essa configuração. Consulte sem escolher servidor:

```sh
docker compose -p bind9-local -f compose.local.yml run --rm --no-deps cliente sh -ec 'getent hosts app.lab.test; dig +time=10 +tries=1 app.lab.test A; dig +time=10 +tries=1 +tcp app.lab.test A'
```

No Docker Desktop, os IPs internos não ficam diretamente acessíveis pela LAN.
A publicação atual atende somente localhost. Acesso por outras máquinas exige
publicação e firewall adequados ou encaminhamento por VPN, túnel ou proxy com
suporte a DNS UDP/TCP; uma VPN sozinha não publica a rede interna. Outros projetos
precisam de rede compartilhada ou caminho até os servidores. Novos serviços
precisam de registros DNS próprios; não são cadastrados automaticamente.

## Falha, persistência e recuperação

Depois de `normal` passar, pare o primário e recrie somente o secundário:

```sh
docker compose -p bind9-local -f compose.local.yml stop dns-primario
docker compose -p bind9-local -f compose.local.yml run --rm --no-deps cliente sh /testes/verificar.sh falha
docker compose -p bind9-local -f compose.local.yml up -d --no-deps --force-recreate --wait --wait-timeout 120 dns-secundario
docker compose -p bind9-local -f compose.local.yml run --rm --no-deps cliente sh /testes/verificar.sh falha
```

O secundário deve responder nos dois testes, usando a zona persistida. Não remova
os volumes; execute antes da expiração do SOA. Repita a consulta sem servidor
explícito para testar a seleção do secundário: a troca depende de timeouts.

```sh
docker compose -p bind9-local -f compose.local.yml up -d --wait --wait-timeout 120 dns-primario
docker compose -p bind9-local -f compose.local.yml run --rm --no-deps cliente sh /testes/verificar.sh normal
```

Para a apresentação, siga a divisão de tempo do [roteiro](roteiro-demo.md),
usando a parada do contêiner em lugar do desligamento da VM.

## Limpeza

`down` sem `--volumes` preserva os dados; suba novamente e repita `normal` para
conferir. Ao terminar, remova somente os recursos deste projeto:

```sh
docker compose -p bind9-local -f compose.local.yml down --volumes --remove-orphans
docker ps -a --filter label=com.docker.compose.project=bind9-local
docker network ls --filter label=com.docker.compose.project=bind9-local
docker volume ls --filter label=com.docker.compose.project=bind9-local
```

As listagens devem ficar sem recursos do projeto, e as portas devem ser liberadas.
Remova apenas o `.env.local` criado para o teste, se não for reutilizado.
Imagens continuam em cache: compare com o inventário anterior e remova somente
as novas e sem uso. Preserve recursos preexistentes; não use limpeza global,
restauração de fábrica ou exclusão de distribuições WSL.

Referências: [rede do Docker Desktop](https://docs.docker.com/desktop/features/networking/),
[WSL 2](https://docs.docker.com/desktop/features/wsl/) e
[limpeza Compose](https://docs.docker.com/reference/cli/docker/compose/down/).
