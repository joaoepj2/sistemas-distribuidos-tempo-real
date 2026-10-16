# Verifica o registro A do exercicio nas portas publicadas pelo Compose local.
# Usa sockets nativos, sem alterar o DNS do Windows nem instalar dependencias.
[CmdletBinding()]
param(
    [ValidateRange(1, 65535)][int]$PortaPrimario = 1053,
    [ValidateRange(1, 65535)][int]$PortaSecundario = 2053,
    [ValidateRange(100, 30000)][int]$TimeoutMs = 3000
)
$ErrorActionPreference = 'Stop'

function Read-Exact([System.IO.Stream]$Stream, [int]$Count) {
    $buffer = New-Object byte[] $Count
    $offset = 0
    while ($offset -lt $Count) {
        $received = $Stream.Read($buffer, $offset, $Count - $offset)
        if ($received -eq 0) { throw 'Resposta TCP incompleta' }
        $offset += $received
    }
    return ,$buffer
}

function Get-U16([byte[]]$Data, [int]$Offset) {
    if ($Offset + 1 -ge $Data.Length) { throw 'Resposta DNS incompleta' }
    return ([int]$Data[$Offset] -shl 8) -bor [int]$Data[$Offset + 1]
}

function Skip-Name([byte[]]$Data, [int]$Offset) {
    while ($Offset -lt $Data.Length) {
        $size = [int]$Data[$Offset]
        if (($size -band 192) -eq 192) {
            if ($Offset + 1 -ge $Data.Length) { throw 'Nome DNS incompleto' }
            return $Offset + 2
        }
        if ($size -gt 63) { throw 'Rotulo DNS invalido' }
        $Offset += 1 + $size
        if ($size -eq 0) { return $Offset }
    }
    throw 'Nome DNS incompleto'
}

function Confirm-Answer([byte[]]$Data) {
    # ID 0x1234, resposta autoritativa sem erro, uma pergunta e resposta A esperada.
    if ($Data.Length -lt 12 -or (Get-U16 $Data 0) -ne 4660) { throw 'ID DNS invalido' }
    $flags = Get-U16 $Data 2
    if (($flags -band 32768) -eq 0 -or ($flags -band 1024) -eq 0 -or ($flags -band 15) -ne 0 -or ($flags -band 512) -ne 0) {
        throw 'Esperada resposta DNS autoritativa, completa e sem erro'
    }
    if ((Get-U16 $Data 4) -ne 1) { throw 'Pergunta DNS inesperada' }
    $offset = (Skip-Name $Data 12) + 4
    $answerCount = Get-U16 $Data 6
    for ($answerIndex = 0; $answerIndex -lt $answerCount; $answerIndex++) {
        $offset = Skip-Name $Data $offset
        $recordType = Get-U16 $Data $offset
        $recordClass = Get-U16 $Data ($offset + 2)
        $size = Get-U16 $Data ($offset + 8)
        $offset += 10
        if ($offset + $size -gt $Data.Length) { throw 'Registro DNS incompleto' }
        if ($recordType -eq 1 -and $recordClass -eq 1 -and $size -eq 4) {
            $address = [System.Net.IPAddress]::new([byte[]]$Data[$offset..($offset + 3)])
            if ($address.ToString() -eq '192.0.2.80') { return }
        }
        $offset += $size
    }
    throw 'Resposta A esperada 192.0.2.80 nao encontrada'
}

# Cabecalho e pergunta DNS: app.lab.test, tipo A, classe IN, recursao solicitada.
[byte[]]$query = 18,52,1,0,0,1,0,0,0,0,0,0,3,97,112,112,3,108,97,98,4,116,101,115,116,0,0,1,0,1
foreach ($port in @($PortaPrimario, $PortaSecundario)) {
    $udp = [System.Net.Sockets.UdpClient]::new()
    try {
        $udp.Client.ReceiveTimeout = $TimeoutMs
        $udp.Connect('127.0.0.1', $port)
        $null = $udp.Send($query, $query.Length)
        $remote = [System.Net.IPEndPoint]::new([System.Net.IPAddress]::Any, 0)
        Confirm-Answer ($udp.Receive([ref]$remote))
        Write-Output "OK UDP 127.0.0.1:${port}: app.lab.test A = 192.0.2.80 (autoritativo)"
    } finally { $udp.Dispose() }

    $tcp = [System.Net.Sockets.TcpClient]::new()
    try {
        $pending = $tcp.BeginConnect('127.0.0.1', $port, $null, $null)
        try {
            if (-not $pending.AsyncWaitHandle.WaitOne($TimeoutMs)) { throw 'Timeout TCP' }
            $tcp.EndConnect($pending)
        } finally { $pending.AsyncWaitHandle.Close() }
        $stream = $tcp.GetStream()
        $stream.ReadTimeout = $TimeoutMs
        $stream.WriteTimeout = $TimeoutMs
        [byte[]]$frame = 0, $query.Length
        $stream.Write($frame, 0, 2)
        $stream.Write($query, 0, $query.Length)
        $size = Get-U16 (Read-Exact $stream 2) 0
        Confirm-Answer (Read-Exact $stream $size)
        Write-Output "OK TCP 127.0.0.1:${port}: app.lab.test A = 192.0.2.80 (autoritativo)"
    } finally { $tcp.Dispose() }
}
