# Demonstração — 15 minutos

Prepare antes os IPs fixos, os `.env`, as imagens e a transferência da zona.
Use o [tutorial em máquinas distintas](README.md) ou o [laboratório local](laboratorio-local.md).

| Tempo | Ação | Resultado esperado |
| --- | --- | --- |
| 0–3 min | Apresentar a topologia; iniciar e mostrar `ps -a` | Um BIND por nó, ou dois no modo local; configuradores finalizados |
| 3–10 min | Consultar os registros, comparar SOA e logs; executar `normal` | Respostas previstas e transferência TSIG; colega consulta pela LAN no modo entre máquinas |
| 10–15 min | Parar o primário; executar `falha`; recriar o secundário preservando volumes; recuperar e repetir `normal` | Secundário responde durante a falha; ambos respondem após recuperação |

No modo entre máquinas, desligue somente a VM primária pelo hipervisor e use
os comandos da seção 7 do tutorial. No modo local, use os comandos de falha do
guia local: eles param apenas `dns-primario` e recriam `dns-secundario`.

Plano B: com as VMs ligadas, `docker compose stop dns` no primário demonstra
falha de serviço. Recupere com `docker compose up -d --wait`. Tenha as imagens
baixadas e uma gravação preparada para falha de rede durante a apresentação.

Feche relacionando replicação de zona e disponibilidade: o secundário mantém
uma cópia até a expiração do SOA; trocar de DNS automaticamente depende do
resolvedor. Encerre e limpe conforme o guia escolhido.
