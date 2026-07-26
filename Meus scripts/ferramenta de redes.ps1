<#
.SYNOPSIS
    Script de diagnóstico, redefinição de rede e calibração de MTU.
.AUTHOR
    Fabiopsyduck
#>

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
Import-Module NetTCPIP -ErrorAction SilentlyContinue

# =====================================================================
# BLOCO DE AUTO-ELEVAÇÃO DE PRIVILÉGIOS (Requer Administrador)
# =====================================================================
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    Write-Host "Solicitando privilégios de Administrador..." -ForegroundColor Yellow
    try {
        Start-Process powershell -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
        exit
    } catch {
        Write-Host "Falha ao obter privilégios. Execute o script como Administrador manualmente." -ForegroundColor Red
        Pause
        exit
    }
}
# =====================================================================

# =====================================================================
# FUNÇÕES DE INTERFACE E FERRAMENTAS
# =====================================================================

# Função para Opções 1 e 2 (Painel de Execução Visual)
function Executar-ComandoComInterface {
    param (
        [array]$Comandos
    )

    [console]::CursorVisible = $false
    $logEventos = @()
    
    foreach ($item in $Comandos) {
        $item | Add-Member -MemberType NoteProperty -Name "Status" -Value "Em espera"
    }

    for ($i = 0; $i -lt $Comandos.Count; $i++) {
        $Comandos[$i].Status = "Em andamento"
        
        & {
            Clear-Host
            Write-Host "===================================================" -ForegroundColor Cyan
            Write-Host "                PAINEL DE EXECUÇÃO                 " -ForegroundColor Cyan
            Write-Host "===================================================" -ForegroundColor Cyan
            Write-Host ""
            
            foreach ($item in $Comandos) {
                $textoComando = $item.Cmd.PadRight(30)
                if ($item.Status -eq "Em espera") {
                    Write-Host "$textoComando : " -NoNewline; Write-Host $item.Status -ForegroundColor DarkGray
                } elseif ($item.Status -eq "Em andamento") {
                    Write-Host "$textoComando : " -NoNewline; Write-Host $item.Status -ForegroundColor Yellow
                } elseif ($item.Status -eq "Concluído") {
                    Write-Host "$textoComando : " -NoNewline; Write-Host $item.Status -ForegroundColor Green
                }
            }
            
            Write-Host "`n---------------------------------------------------"
            Write-Host "REGISTRO DE EVENTOS:"
            if ($logEventos.Count -gt 0) {
                foreach ($log in $logEventos) {
                    Write-Host "- $log" -ForegroundColor Gray
                }
            }
            Write-Host "- (Aguardando...)" -ForegroundColor DarkGray
            Write-Host "===================================================" -ForegroundColor Cyan
        }
        
        Invoke-Expression $Comandos[$i].Cmd 2>&1 | Out-Null
        
        $Comandos[$i].Status = "Concluído"
        $logEventos += $Comandos[$i].Info
    }

    Clear-Host
    Write-Host "===================================================" -ForegroundColor Cyan
    Write-Host "                PAINEL DE EXECUÇÃO                 " -ForegroundColor Cyan
    Write-Host "===================================================" -ForegroundColor Cyan
    Write-Host ""
    foreach ($item in $Comandos) {
        $textoComando = $item.Cmd.PadRight(30)
        Write-Host "$textoComando : " -NoNewline; Write-Host $item.Status -ForegroundColor Green
    }
    Write-Host "`n---------------------------------------------------"
    Write-Host "REGISTRO DE EVENTOS:"
    foreach ($log in $logEventos) {
        Write-Host "- $log" -ForegroundColor Gray
    }
    Write-Host "===================================================" -ForegroundColor Cyan
    [console]::CursorVisible = $true
}

# Função Auxiliar da Opção 3 (Mini-Flood)
function ExecutarMiniFlood {
    param (
        [string]$TargetIP,
        [int]$PayloadSize,
        [string]$Fase,
        [bool]$IsIPv6
    )
    
    Write-Host "  [➔] Iniciando Mini-Flood de $($Fase): 100 pacotes ($PayloadSize bytes de payload)..." -ForegroundColor Yellow
    
    $pingObj = New-Object System.Net.NetworkInformation.Ping
    $opt = New-Object System.Net.NetworkInformation.PingOptions
    if (-not $IsIPv6) { $opt.DontFragment = $true }
    
    if ($PayloadSize -le 0) { $PayloadSize = 1472 }
    $buffer = New-Object byte[] $PayloadSize
    (New-Object Random).NextBytes($buffer)
    
    $sucessos = 0
    $falhasBuffer = 0
    $timeouts = 0
    
    for ($i = 1; $i -le 100; $i++) {
        try {
            $res = $pingObj.Send($TargetIP, 400, $buffer, $opt)
            if ($res.Status -eq 'Success') { $sucessos++ }
            elseif ($res.Status -eq 'PacketTooBig') { $falhasBuffer++ }
            else { $timeouts++ }
        } catch { $timeouts++ }
        Start-Sleep -Milliseconds 10
    }
    
    if ($falhasBuffer -gt 0) {
        Write-Host "  └─ RESULTADO: $sucessos/100 OK | Bloqueados por MTU: $falhasBuffer | Perdas: $timeouts" -ForegroundColor Red
        Write-Host "     [!] Bloqueio detectado! A alteração de configuração é altamente necessária." -ForegroundColor Red
    } elseif ($timeouts -gt 15) {
        Write-Host "  └─ RESULTADO: $sucessos/100 OK | Bloqueados: $falhasBuffer | Perdas/Timeout: $timeouts" -ForegroundColor DarkYellow
        Write-Host "     [!] Rota instável ou congestionada detectada durante o estresse." -ForegroundColor Yellow
    } else {
        Write-Host "  └─ RESULTADO: $sucessos/100 OK | Bloqueados: $falhasBuffer | Perdas: $timeouts" -ForegroundColor Green
        Write-Host "     [+] Rota perfeitamente estável e fluida para este tamanho de pacote." -ForegroundColor Green
    }
    Write-Host ""
}

# Função Principal da Opção 3 (Calibrador MTU)
function Executar-CalibradorMTU {
    [console]::CursorVisible = $false

    Clear-Host
    Write-Host "===============================================================" -ForegroundColor Cyan
    Write-Host "            CALIBRADOR AVANÇADO DE LIMITES DE REDE             " -ForegroundColor Cyan
    Write-Host "                    Autor: Fabiopsyduck                        " -ForegroundColor DarkGray
    Write-Host "===============================================================`n" -ForegroundColor Cyan

    Write-Host "SOBRE ESTA FERRAMENTA:" -ForegroundColor Yellow
    Write-Host "Este utilitário diagnostica o limite físico da sua conexão (MTU)"
    Write-Host "e aplica a configuração exata no Windows para evitar perda de"
    Write-Host "pacotes, reduzir o atraso (jitter) e otimizar rotas de rede.`n"

    Write-Host "AVISO DE PRECISÃO:" -ForegroundColor Red
    Write-Host "Para evitar interferência na medição de pacotes, suspenda"
    Write-Host "temporariamente antes de iniciar:"
    Write-Host " - Downloads e Uploads ativos"
    Write-Host " - Streaming de vídeo e áudio"
    Write-Host " - Jogos online em andamento`n"

    Write-Host "[ENTER] Iniciar testes de rede | [ESC] Voltar ao Menu Principal" -ForegroundColor Cyan
    
    $keyIntro = $null
    while ($keyIntro -notin @('Enter', 'Escape')) {
        $keyIntro = [console]::ReadKey($true).Key
    }
    
    if ($keyIntro -eq 'Escape') {
        [console]::CursorVisible = $true
        return
    }

    $adapter = Get-NetAdapter | Where-Object { $_.Status -eq 'Up' -and $_.Virtual -eq $false } | Select-Object -First 1

    if (-not $adapter) {
        Write-Host "`nNenhuma placa de rede física ativa foi encontrada." -ForegroundColor Red
        Write-Host "[ENTER] Voltar ao Menu Principal" -ForegroundColor Cyan
        $null = [console]::ReadKey($true)
        [console]::CursorVisible = $true
        return
    }

    Clear-Host
    Write-Host "===============================================================" -ForegroundColor Cyan
    Write-Host "            CALIBRADOR AVANÇADO DE LIMITES DE REDE             " -ForegroundColor Cyan
    Write-Host "===============================================================`n" -ForegroundColor Cyan

    Write-Host "[1] PLACA DE REDE ATIVA" -ForegroundColor Yellow
    Write-Host "Nome: $($adapter.Name)"
    Write-Host "Velocidade de Conexão: $($adapter.LinkSpeed)`n"

    Write-Host "[2] LIMITE LOCAL DO WINDOWS (MTU)" -ForegroundColor Yellow

    $netshOutputV4 = netsh interface ipv4 show subinterfaces
    $mtuLineV4 = $netshOutputV4 | Where-Object { $_ -match [regex]::Escape($adapter.Name) }
    $currentMTU_v4 = "Desconhecido"
    if ($mtuLineV4 -match "^\s*(\d+)") { $currentMTU_v4 = [int]$matches[1] }

    $netshOutputV6 = netsh interface ipv6 show subinterfaces
    $mtuLineV6 = $netshOutputV6 | Where-Object { $_ -match [regex]::Escape($adapter.Name) }
    $currentMTU_v6 = "Desconhecido"
    if ($mtuLineV6 -match "^\s*(\d+)") { $currentMTU_v6 = [int]$matches[1] }

    Write-Host "-> MTU IPv4 detectado: $currentMTU_v4 bytes" -ForegroundColor DarkGray
    Write-Host "-> MTU IPv6 detectado: $currentMTU_v6 bytes" -ForegroundColor DarkGray

    $hasCustomMTUV4 = ($currentMTU_v4 -ne "Desconhecido" -and $currentMTU_v4 -ne 1500)
    $hasCustomMTUV6 = ($currentMTU_v6 -ne "Desconhecido" -and $currentMTU_v6 -ne 1500)

    if ($hasCustomMTUV4 -or $hasCustomMTUV6) {
        $actionMTUV4 = "MANTER"
        $actionMTUV6 = "MANTER"
        $menuActive = $true

        while ($menuActive) {
            Clear-Host
            Write-Host "===============================================================" -ForegroundColor Cyan
            Write-Host "            CALIBRADOR AVANÇADO DE LIMITES DE REDE             " -ForegroundColor Cyan
            Write-Host "===============================================================`n" -ForegroundColor Cyan
            
            Write-Host "[1] PLACA DE REDE ATIVA" -ForegroundColor Yellow
            Write-Host "Nome: $($adapter.Name)`n"
            
            Write-Host "[2] LIMITE LOCAL DO WINDOWS (MTU)" -ForegroundColor Yellow
            Write-Host "-> MTU IPv4 detectado: $currentMTU_v4 bytes" -ForegroundColor DarkGray
            Write-Host "-> MTU IPv6 detectado: $currentMTU_v6 bytes`n" -ForegroundColor DarkGray

            Write-Host "CONFIGURAÇÕES CUSTOMIZADAS DETECTADAS:" -ForegroundColor Yellow
            Write-Host "Use o teclado para alternar as opções. Pressione ENTER para confirmar.`n"

            if ($hasCustomMTUV4) {
                $colorMTUV4 = if ($actionMTUV4 -eq "MANTER") { "Green" } else { "Red" }
                Write-Host "[$actionMTUV4] " -NoNewline -ForegroundColor $colorMTUV4
                Write-Host "Configuração MTU IPv4 ($currentMTU_v4)"
            }

            if ($hasCustomMTUV6) {
                $colorMTUV6 = if ($actionMTUV6 -eq "MANTER") { "Green" } else { "Red" }
                Write-Host "[$actionMTUV6] " -NoNewline -ForegroundColor $colorMTUV6
                Write-Host "Configuração MTU IPv6 ($currentMTU_v6)"
            }

            Write-Host "`n"

            if ($hasCustomMTUV4) {
                $instMTUV4 = if ($actionMTUV4 -eq "MANTER") { "remover" } else { "manter " }
                Write-Host "[ F1 ] Para $instMTUV4 `"Configuração MTU IPv4`"" -ForegroundColor Cyan
            }
            if ($hasCustomMTUV6) {
                $instMTUV6 = if ($actionMTUV6 -eq "MANTER") { "remover" } else { "manter " }
                Write-Host "[ F2 ] Para $instMTUV6 `"Configuração MTU IPv6`"" -ForegroundColor Cyan
            }
            Write-Host "[ENTER] Confirmar e Iniciar Testes" -ForegroundColor Cyan

            $key = [console]::ReadKey($true).Key
            if ($key -eq 'F1' -and $hasCustomMTUV4) { $actionMTUV4 = if ($actionMTUV4 -eq "MANTER") { "REMOVER" } else { "MANTER" } } 
            elseif ($key -eq 'F2' -and $hasCustomMTUV6) { $actionMTUV6 = if ($actionMTUV6 -eq "MANTER") { "REMOVER" } else { "MANTER" } } 
            elseif ($key -eq 'Enter') { $menuActive = $false }
        }

        Write-Host "`nProcessando configurações iniciais... " -ForegroundColor Yellow
        if ($hasCustomMTUV4 -and $actionMTUV4 -eq "REMOVER") {
            Write-Host "Restaurando MTU IPv4 para 1500... " -NoNewline
            netsh interface ipv4 set subinterface "$($adapter.Name)" mtu=1500 store=persistent | Out-Null
            $currentMTU_v4 = 1500
            Write-Host "OK!" -ForegroundColor Green
        }
        if ($hasCustomMTUV6 -and $actionMTUV6 -eq "REMOVER") {
            Write-Host "Restaurando MTU IPv6 para 1500... " -NoNewline
            netsh interface ipv6 set subinterface "$($adapter.Name)" mtu=1500 store=persistent | Out-Null
            $currentMTU_v6 = 1500
            Write-Host "OK!" -ForegroundColor Green
        }
        Start-Sleep -Seconds 1
    } else {
        Write-Host "`n[ENTER] Confirmar e Iniciar Testes" -ForegroundColor Cyan
        $null = [console]::ReadKey($true)
    }

    Clear-Host
    # ======================================================================
    # 3. BENCHMARK E TESTE PRÁTICO (IPv4)
    # ======================================================================
    Write-Host "[3] SELEÇÃO DE ROTA E AUDITORIA DE ESTRESSE (IPv4)" -ForegroundColor Yellow

    $serversV4 = @(
        [pscustomobject]@{ Nome="Quad9 (Primário)"; IP="9.9.9.10" },
        [pscustomobject]@{ Nome="Quad9 (Secundário)"; IP="149.112.112.10" },
        [pscustomobject]@{ Nome="AdGuard (Primário)"; IP="94.140.14.14" },
        [pscustomobject]@{ Nome="AdGuard (Secundário)"; IP="94.140.15.15" },
        [pscustomobject]@{ Nome="ControlD (Primário)"; IP="76.76.2.0" },
        [pscustomobject]@{ Nome="ControlD (Secundário)"; IP="76.76.10.0" }
    )

    $bestServerV4 = $null
    $lowestPingV4 = 99999
    $timeoutV4 = 500

    Write-Host "Realizando Benchmark nos servidores DNS..." -ForegroundColor DarkGray
    foreach ($srv in $serversV4) {
        Write-Host "  ├─ $($srv.Nome) ($($srv.IP))... " -NoNewline
        $benchPing = ping.exe $srv.IP -n 4
        $times = @()
        foreach ($line in $benchPing) { if ($line -match "(?i)(?:time|tempo)[=<]\s*(\d+)\s*ms") { $times += [int]$matches[1] } }
        
        if ($times.Count -gt 0) {
            $avgPing = ($times | Measure-Object -Average).Average
            Write-Host "$([math]::Round($avgPing)) ms" -ForegroundColor Cyan
            if ($avgPing -lt $lowestPingV4) { $lowestPingV4 = $avgPing; $bestServerV4 = $srv; $timeoutV4 = [math]::Max([int]($avgPing * 1.5), 100) }
        } else { Write-Host "Falha" -ForegroundColor Red }
    }

    $globalMTUs_v4 = @()
    if ($bestServerV4 -ne $null) {
        Write-Host "  └─ Vencedor IPv4: $($bestServerV4.Nome) ($([math]::Round($lowestPingV4)) ms)`n" -ForegroundColor Green
        
        Write-Host "* AUDITORIA INICIAL: Testando MTU configurado" -ForegroundColor Cyan
        $payloadAntesV4 = if ($currentMTU_v4 -eq "Desconhecido") { 1472 } else { $currentMTU_v4 - 28 }
        ExecutarMiniFlood -TargetIP $bestServerV4.IP -PayloadSize $payloadAntesV4 -Fase "ANTES" -IsIPv6 $false
        
        Write-Host "* VARREDURA DE LIMITES FÍSICOS: Procurando MTU Ótimo..." -ForegroundColor Cyan
        $maxPayloadV4 = 1472
        
        if ($currentMTU_v4 -ne "Desconhecido" -and $currentMTU_v4 -lt 1500) { $maxPayloadV4 = $currentMTU_v4 - 28 }
        
        $minPayloadV4 = 1400
        $testHistory = @()
        
        for ($i = 1; $i -le 50; $i++) {
            Write-Host "`r  ├─ Analisando comportamento da rota: $i/50" -NoNewline -ForegroundColor Yellow
            $optimalPayload = 0
            for ($size = $maxPayloadV4; $size -ge $minPayloadV4; $size -= 2) {
                $ping = ping.exe $bestServerV4.IP -f -l $size -n 1 -w $timeoutV4
                Start-Sleep -Milliseconds 30
                if ($ping -match "Resposta de" -or $ping -match "Reply from") { $optimalPayload = $size; break }
            }
            if ($optimalPayload -ne 0) { $finalMTU = $optimalPayload + 28; $testHistory += $finalMTU; $globalMTUs_v4 += $finalMTU }
        }
        Write-Host ""
        
        $uniqueMTUs = $testHistory | Select-Object -Unique
        if ($uniqueMTUs.Count -gt 0) {
            $joinedMTUs = $uniqueMTUs -join ", "
            if ($uniqueMTUs.Count -eq 1) { 
                Write-Host "  └─ Limite Físico Descoberto: $joinedMTUs bytes" -ForegroundColor Green 
                Write-Host "`n* AUDITORIA DE VALIDAÇÃO: Testando nova configuração proposta" -ForegroundColor Cyan
                ExecutarMiniFlood -TargetIP $bestServerV4.IP -PayloadSize ($uniqueMTUs[0] - 28) -Fase "DEPOIS" -IsIPv6 $false
            } else { Write-Host "  └─ Limite Físico Descoberto: $joinedMTUs (Rota Instável)" -ForegroundColor Red }
        }
    }

    # ======================================================================
    # 4. BENCHMARK E TESTE PRÁTICO (IPv6)
    # ======================================================================
    Write-Host "`n[4] SELEÇÃO DE ROTA E AUDITORIA DE ESTRESSE (IPv6)" -ForegroundColor Yellow

    $ipv6Active = $false
    Write-Host "Verificando conectividade IPv6... " -NoNewline -ForegroundColor DarkGray
    $testPingV6 = ping.exe -6 2606:4700:4700::1111 -n 1 -w 1000
    if ($testPingV6 -match "Resposta de" -or $testPingV6 -match "Reply from") {
        Write-Host "Ativo!" -ForegroundColor Green
        $ipv6Active = $true
    } else { Write-Host "Sem resposta (Ignorado)." -ForegroundColor Red }

    $globalMTUs_v6 = @()

    if ($ipv6Active) {
        $serversV6 = @(
            [pscustomobject]@{ Nome="Quad9 (Primário)"; IP="2620:fe::10" },
            [pscustomobject]@{ Nome="Quad9 (Secundário)"; IP="2620:fe::fe:10" },
            [pscustomobject]@{ Nome="AdGuard (Primário)"; IP="2a10:50c0::1:ff" },
            [pscustomobject]@{ Nome="AdGuard (Secundário)"; IP="2a10:50c0::2:ff" },
            [pscustomobject]@{ Nome="ControlD (Primário)"; IP="2606:1a40::" },
            [pscustomobject]@{ Nome="ControlD (Secundário)"; IP="2606:1a40:1::" }
        )

        $bestServerV6 = $null
        $lowestPingV6 = 99999
        $timeoutV6 = 500

        Write-Host "Realizando Benchmark nos servidores DNS..." -ForegroundColor DarkGray
        foreach ($srv in $serversV6) {
            Write-Host "  ├─ $($srv.Nome) ($($srv.IP))... " -NoNewline
            $benchPing = ping.exe -6 $srv.IP -n 4
            $times = @()
            foreach ($line in $benchPing) { if ($line -match "(?i)(?:time|tempo)[=<]\s*(\d+)\s*ms") { $times += [int]$matches[1] } }
            
            if ($times.Count -gt 0) {
                $avgPing = ($times | Measure-Object -Average).Average
                Write-Host "$([math]::Round($avgPing)) ms" -ForegroundColor Cyan
                if ($avgPing -lt $lowestPingV6) { $lowestPingV6 = $avgPing; $bestServerV6 = $srv; $timeoutV6 = [math]::Max([int]($avgPing * 1.5), 100) }
            } else { Write-Host "Falha" -ForegroundColor Red }
        }
        
        if ($bestServerV6 -ne $null) {
            Write-Host "  └─ Vencedor IPv6: $($bestServerV6.Nome) ($([math]::Round($lowestPingV6)) ms)`n" -ForegroundColor Green
            
            Write-Host "* AUDITORIA INICIAL: Testando MTU configurado" -ForegroundColor Cyan
            $payloadAntesV6 = if ($currentMTU_v6 -eq "Desconhecido") { 1452 } else { $currentMTU_v6 - 48 }
            ExecutarMiniFlood -TargetIP $bestServerV6.IP -PayloadSize $payloadAntesV6 -Fase "ANTES" -IsIPv6 $true
            
            Write-Host "* VARREDURA DE LIMITES FÍSICOS: Procurando MTU Ótimo..." -ForegroundColor Cyan
            
            $maxPayloadV6 = 1452
            
            if ($currentMTU_v6 -ne "Desconhecido" -and $currentMTU_v6 -lt 1500) {
                $maxPayloadV6 = $currentMTU_v6 - 48
            }
            
            $minPayloadV6 = 1352
            $testHistory = @()
            
            for ($i = 1; $i -le 50; $i++) {
                Write-Host "`r  ├─ Analisando comportamento da rota: $i/50" -NoNewline -ForegroundColor Yellow
                $optimalPayload = 0
                for ($size = $maxPayloadV6; $size -ge $minPayloadV6; $size -= 2) {
                    $ping = ping.exe -6 $bestServerV6.IP -l $size -n 1 -w $timeoutV6
                    Start-Sleep -Milliseconds 30
                    if ($ping -match "Resposta de" -or $ping -match "Reply from") { $optimalPayload = $size; break }
                }
                if ($optimalPayload -ne 0) { $finalMTU = $optimalPayload + 48; $testHistory += $finalMTU; $globalMTUs_v6 += $finalMTU }
            }
            Write-Host ""
            
            $uniqueMTUs = $testHistory | Select-Object -Unique
            if ($uniqueMTUs.Count -gt 0) {
                $joinedMTUs = $uniqueMTUs -join ", "
                if ($uniqueMTUs.Count -eq 1) { 
                    Write-Host "  └─ Limite Físico Descoberto: $joinedMTUs bytes" -ForegroundColor Green 
                    Write-Host "`n* AUDITORIA DE VALIDAÇÃO: Testando nova configuração proposta" -ForegroundColor Cyan
                    ExecutarMiniFlood -TargetIP $bestServerV6.IP -PayloadSize ($uniqueMTUs[0] - 48) -Fase "DEPOIS" -IsIPv6 $true
                } else { Write-Host "  └─ Limite Físico Descoberto: $joinedMTUs (Rota Instável)" -ForegroundColor Red }
            }
        }
    }

    Write-Host "`n[ENTER] Exibir Conclusão e Resultados Finais" -ForegroundColor Cyan
    $null = [console]::ReadKey($true)
    Clear-Host

    # ======================================================================
    # 5. AVALIAÇÃO FINAL E APLICAÇÃO
    # ======================================================================
    Write-Host "===============================================================" -ForegroundColor Cyan
    Write-Host "             RESULTADO FINAL (CONFIGURAÇÃO MTU)                " -ForegroundColor Yellow
    Write-Host "===============================================================`n" -ForegroundColor Cyan

    $uniqueGlobalMTUs_v4 = $globalMTUs_v4 | Select-Object -Unique | Sort-Object -Descending
    $recommendedMTU_v4 = 0
    $recommendedMTU_v6 = 0
    $needToApplyV4 = $false
    $needToApplyV6 = $false

    if ($uniqueGlobalMTUs_v4.Count -gt 0) {
        $recommendedMTU_v4 = ($uniqueGlobalMTUs_v4 | Measure-Object -Minimum).Minimum
        Write-Host "RECOMENDAÇÃO DE HARDWARE (IPv4):" -ForegroundColor Yellow
        Write-Host "MTU Ideal Encontrado: $recommendedMTU_v4 bytes" -ForegroundColor Green
        
        if ($currentMTU_v4 -ne "Desconhecido" -and $recommendedMTU_v4 -eq $currentMTU_v4) {
            Write-Host "Status IPv4: Perfeito! O Windows já está configurado com esse valor.`n" -ForegroundColor Cyan
        } else {
            Write-Host "Status IPv4: O Windows está usando $currentMTU_v4. Recomendado alterar para $recommendedMTU_v4.`n" -ForegroundColor Red
            $needToApplyV4 = $true
        }
    }

    if ($ipv6Active -and $globalMTUs_v6.Count -gt 0) {
        $uniqueGlobalMTUs_v6 = $globalMTUs_v6 | Select-Object -Unique | Sort-Object -Descending
        $recommendedMTU_v6 = ($uniqueGlobalMTUs_v6 | Measure-Object -Minimum).Minimum
        Write-Host "RECOMENDAÇÃO DE HARDWARE (IPv6):" -ForegroundColor Yellow
        Write-Host "MTU Ideal Encontrado: $recommendedMTU_v6 bytes" -ForegroundColor Green
        
        if ($currentMTU_v6 -ne "Desconhecido" -and $recommendedMTU_v6 -eq $currentMTU_v6) {
            Write-Host "Status IPv6: Perfeito! O Windows já está configurado com esse valor.`n" -ForegroundColor Cyan
        } else {
            Write-Host "Status IPv6: O Windows está usando $currentMTU_v6. Recomendado alterar para $recommendedMTU_v6.`n" -ForegroundColor Red
            $needToApplyV6 = $true
        }
    }

    if ($needToApplyV4 -or $needToApplyV6) {
        [console]::CursorVisible = $true 
        $applyChoice = Read-Host "Deseja aplicar os MTUs recomendados agora? (S/N)"
        [console]::CursorVisible = $false 
        
        if ($applyChoice -match "^[Ss]$") {
            Write-Host "`nAplicando configurações... " -ForegroundColor Cyan
            if ($needToApplyV4) {
                netsh interface ipv4 set subinterface "$($adapter.Name)" mtu=$recommendedMTU_v4 store=persistent | Out-Null
                Write-Host "IPv4 alterado para $recommendedMTU_v4 com sucesso!" -ForegroundColor Green
            }
            if ($needToApplyV6) {
                netsh interface ipv6 set subinterface "$($adapter.Name)" mtu=$recommendedMTU_v6 store=persistent | Out-Null
                Write-Host "IPv6 alterado para $recommendedMTU_v6 com sucesso!" -ForegroundColor Green
            }
        } else { Write-Host "`nNenhuma alteração foi feita no MTU do sistema." -ForegroundColor DarkGray }
    }
    
    Write-Host "`n[+] Processo do Calibrador MTU finalizado." -ForegroundColor Green
    [console]::CursorVisible = $false
    Write-Host "[ENTER] Voltar ao Menu Principal" -ForegroundColor Cyan
    $null = [console]::ReadKey($true)
    [console]::CursorVisible = $true 
}

# Função da Opção 4 (Configurações Avançadas)
function Show-NetworkAdapterConfig {
    param(
        [string]$SelectedAdapter = $null
    )

    # Variáveis globais
    $script:currentAdapter = ""
    $script:screenContent = ""
    $script:displayProperties = @()

    # Função para mostrar o menu de opções
    function Show-Menu {
        Write-Host ""
        Write-Host "Legenda: " -NoNewline
        Write-Host "(Vermelho)" -ForegroundColor Red -NoNewline
        Write-Host " Configuração que precisa ser modificada."
        Write-Host "         " -NoNewline
        Write-Host "(Verde)" -ForegroundColor Green -NoNewline
        Write-Host " Configuração recomendada para melhor latência e estabilidade."
        Write-Host ""

        Write-Host "Aperte:"
        Write-Host "(A) Para atualizar a leitura de configuração"
        Write-Host "(C) Para abrir conexões de rede"
        Write-Host "(S) Para salvar os resultados da leitura atual"
        Write-Host "(V) Para selecionar outro adaptador"
    }

    # Função para capturar o conteúdo da tela (apenas as configurações)
    function Get-ScreenContent {
        param(
            [string]$adapterName,
            [array]$properties
        )

        $content = @()
        $content += "Configurações relevantes para jogos - '$adapterName':"
        $content += ""
        $content += "DisplayName".PadRight(40) + "RegistryKeyword".PadRight(30) + "DisplayValue".PadRight(20)
        $content += "-----------".PadRight(40) + "---------------".PadRight(30) + "------------".PadRight(20)

        foreach ($prop in $properties) {
            $line = $prop.DisplayName.PadRight(40) + $prop.RegistryKeyword.PadRight(30) + $prop.DisplayValue.PadRight(20)
            $content += $line
        }

        return ($content -join "`n")
    }

    # Função para salvar o conteúdo da tela
    function Save-ScreenContent {
        # Tentar vários locais possíveis para salvar
        $locations = @()
        
        # 1. Pasta do script (se disponível)
        if ($PSScriptRoot -ne "") {
            $locations += $PSScriptRoot
        }
        
        # 2. Diretório de trabalho atual
        $locations += (Get-Location).Path
        
        # 3. Pasta TEMP do usuário
        $locations += $env:TEMP

        $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
        $fileName = "ConfigRede_${script:currentAdapter}_${timestamp}.txt"

        foreach ($location in $locations) {
            $filePath = Join-Path -Path $location -ChildPath $fileName
            
            try {
                # Salva apenas as configurações geradas pelo Get-ScreenContent
                $script:screenContent | Out-File -FilePath $filePath -Encoding UTF8 -ErrorAction Stop
                
                # Mostra mensagem e atualiza a tela
                Clear-Host
                Write-Host "Configurações salvas em: $filePath" -ForegroundColor Green
                Start-Sleep -Seconds 2
                
                # Recarrega as configurações
                Show-AdapterSettings $script:currentAdapter
                return
            }
            catch {
                # Continua para tentar o próximo local
                continue
            }
        }

        # Se todos os locais falharem
        Write-Host "`nNão foi possível salvar o arquivo em nenhum dos locais tentados." -ForegroundColor Red
        Write-Host "Verifique as permissões ou tente executar como administrador." -ForegroundColor Yellow
        $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
    }

    # Helper genérico para descobrir o valor numérico máximo de qualquer propriedade no driver
    function Get-MaxNumericPropertyValue {
        param([string]$AdapterName, [string]$Keyword)
        
        $prop = Get-NetAdapterAdvancedProperty -Name $AdapterName -RegistryKeyword $Keyword -ErrorAction SilentlyContinue
        if (-not $prop) { return $null }

        $maxNum = 0
        foreach ($option in $prop.ValidDisplayValues) {
            # Procura por números dentro das opções disponíveis
            if ($option -match '\d+') {
                $currentNum = [int]$matches[0]
                if ($currentNum -gt $maxNum) { $maxNum = $currentNum }
            }
        }
        return $maxNum
    }

    # Função principal para mostrar configurações
    function Show-AdapterSettings {
        param(
            [string]$adapterName
        )

        $script:currentAdapter = $adapterName

        try {
            # Lista completa de propriedades relevantes (ATUALIZADA com opções de energia/WoL)
            $relevantKeywords = @(
                '*EEE', 'EnableGreenEthernet', 'PowerSavingMode', 'GigaLite', 'AdvancedEEE',
                '*SpeedDuplex', '*FlowControl', '*InterruptModeration', 
                '*LsoV2IPv4', '*LsoV2IPv6', '*RscIPv4', '*RscIPv6',
                '*ReceiveBuffers', '*TransmitBuffers',
                '*RSS', '*NumRssQueues', 'AutoDisableGigabit',
                '*WakeOnPattern', 'S5WakeOnLan', '*WakeOnMagicPacket', 
                '*ModernStandbyWoLMagicPacket', 'WolShutdownLinkSpeed',
                '*PMARPOffload', '*PMNSOffload'
            )
            
            # Obter propriedades
            $properties = Get-NetAdapterAdvancedProperty -Name $adapterName -ErrorAction Stop | 
                          Where-Object { $relevantKeywords -contains $_.RegistryKeyword } |
                          Select-Object DisplayName, DisplayValue, RegistryKeyword, RegistryValue
            
            # Obter informações adicionais do adaptador
            $adapterInfo = Get-NetAdapter -Name $adapterName

            # Extrair os limites máximos (Teto) que o hardware permite para essas 3 propriedades
            $maxRss = Get-MaxNumericPropertyValue -AdapterName $adapterName -Keyword "*NumRssQueues"
            $maxRx  = Get-MaxNumericPropertyValue -AdapterName $adapterName -Keyword "*ReceiveBuffers"
            $maxTx  = Get-MaxNumericPropertyValue -AdapterName $adapterName -Keyword "*TransmitBuffers"
            
            # Limpar a tela e mostrar a tabela com cores
            Clear-Host
            Write-Host "Configurações relevantes para jogos - '$adapterName':`n" -ForegroundColor Cyan
            
            # Cabeçalho da tabela sem a coluna UsoCPUrelevan
            Write-Host "DisplayName".PadRight(40) -NoNewline
            Write-Host "RegistryKeyword".PadRight(30) -NoNewline
            Write-Host "DisplayValue".PadRight(20)
            
            Write-Host "-----------".PadRight(40) -NoNewline
            Write-Host "---------------".PadRight(30) -NoNewline
            Write-Host "------------".PadRight(20)

            # Resetar propriedades de exibição
            $script:displayProperties = @()

            # Processar cada propriedade (Fase de coleta)
            foreach ($keyword in $relevantKeywords) {
                $prop = $properties | Where-Object { $_.RegistryKeyword -eq $keyword }
                
                if (-not $prop -and $keyword -in ('*ReceiveBuffers', '*TransmitBuffers')) {
                    # Criar objeto virtual para buffers se não encontrado
                    $prop = [PSCustomObject]@{
                        DisplayName = if ($keyword -eq '*ReceiveBuffers') { 'Receber Memórias Intermédias' } else { 'Transmitir Memórias Intermédias' }
                        RegistryKeyword = $keyword
                        DisplayValue = if ($keyword -eq '*ReceiveBuffers') { $adapterInfo.ReceiveBufferSize } else { $adapterInfo.TransmitBufferSize }
                        RegistryValue = if ($keyword -eq '*ReceiveBuffers') { $adapterInfo.ReceiveBufferSize } else { $adapterInfo.TransmitBufferSize }
                    }
                }
                
                if ($prop) {
                    # Determinar cor com base no impacto para jogos
                    $color = 'Green' # Padrão verde
                    
                    # Valores considerados ruins para jogos (ATUALIZADO com opções de energia/WoL)
                    $badValues = @{
                        '*FlowControl' = @('3')
                        '*InterruptModeration' = @('1')
                        '*LsoV2IPv4' = @('1')
                        '*LsoV2IPv6' = @('1')
                        '*RscIPv4' = @('1')
                        '*RscIPv6' = @('1')
                        '*SpeedDuplex' = @('0')
                        'EnableGreenEthernet' = @('1')
                        'PowerSavingMode' = @('1')
                        '*EEE' = @('1')
                        'GigaLite' = @('1')
                        'AdvancedEEE' = @('1')
                        'AutoDisableGigabit' = @('1')
                        '*RSS' = @('0')
                        '*WakeOnPattern' = @('1')
                        'S5WakeOnLan' = @('1')
                        '*WakeOnMagicPacket' = @('1')
                        '*ModernStandbyWoLMagicPacket' = @('1')
                        'WolShutdownLinkSpeed' = @('1', '2')
                        '*PMARPOffload' = @('1')
                        '*PMNSOffload' = @('1')
                    }
                    
                    # Extrai o valor atual como número para as verificações matemáticas
                    $currentNum = 0
                    if ($prop.DisplayValue -match '\d+') { $currentNum = [int]$matches[0] }

                    # 1. Regra para Filas RSS (Vermelho se não for o máximo)
                    if ($keyword -eq '*NumRssQueues') {
                        if ($maxRss -and $currentNum -lt $maxRss) { $color = 'Red' }
                    } 
                    # 2. Regra para Receber Memórias (Vermelho se não for o máximo)
                    elseif ($keyword -eq '*ReceiveBuffers') {
                        if ($maxRx -and $currentNum -lt $maxRx) { $color = 'Red' }
                    }
                    # 3. Regra para Transmitir Memórias (Vermelho se não for o máximo)
                    elseif ($keyword -eq '*TransmitBuffers') {
                        if ($maxTx -and $currentNum -lt $maxTx) { $color = 'Red' }
                    }
                    # 4. Lógica padrão imune ao idioma para o resto (Liga/Desliga)
                    elseif ($badValues.ContainsKey($prop.RegistryKeyword)) {
                        if ($badValues[$prop.RegistryKeyword] -contains [string]$prop.RegistryValue) {
                            $color = 'Red'
                        }
                    }

                    # Adicionar propriedade na lista para exibição posterior
                    $displayProp = [PSCustomObject]@{
                        DisplayName = $prop.DisplayName
                        RegistryKeyword = $prop.RegistryKeyword
                        DisplayValue = $prop.DisplayValue
                        Color = $color
                    }
                    $script:displayProperties += $displayProp
                }
            }

            # Organizar a lista alfabeticamente pela propriedade DisplayName
            $script:displayProperties = $script:displayProperties | Sort-Object -Property DisplayName

            # Mostrar cada propriedade organizada com a cor apropriada (Fase de exibição)
            foreach ($item in $script:displayProperties) {
                Write-Host $item.DisplayName.PadRight(40) -NoNewline -ForegroundColor $item.Color
                Write-Host $item.RegistryKeyword.PadRight(30) -NoNewline -ForegroundColor $item.Color
                Write-Host $item.DisplayValue.PadRight(20) -ForegroundColor $item.Color
            }

            # Atualizar conteúdo da tela (apenas as configurações organizadas)
            $script:screenContent = Get-ScreenContent -adapterName $adapterName -properties $script:displayProperties

            # Mostrar menu de opções
            Show-Menu
            
            # Processar escolha do usuário
            $choice = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown').Character
            switch ($choice.ToString().ToUpper()) {
                'A' { 
                    # Atualizar configurações
                    Show-AdapterSettings $adapterName
                }
                'C' { 
                    # Abrir conexões de rede
                    Start-Process "control" "ncpa.cpl"
                    Show-AdapterSettings $adapterName
                }
                'S' {
                    # Salvar conteúdo da tela
                    Save-ScreenContent
                }
                'V' { 
                    # Voltar para seleção de adaptador
                    Clear-Host
                    Main-Selection
                }
                default {
                    # Sair do script (retorna ao menu principal)
                    return
                }
            }
        }
        catch {
            Write-Host "`nOcorreu um erro ao acessar as configurações de rede." -ForegroundColor Red
            Write-Host "Detalhes do erro: $_" -ForegroundColor DarkGray
            $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
        }
    }

    # Função para seleção do adaptador
    function Main-Selection {
        try {
            # O @() garante que o resultado seja tratado como Array, mesmo se houver apenas 1 adaptador
            $adapters = @(Get-NetAdapter -ErrorAction Stop | Sort-Object -Property Name)
            
            if ($adapters.Count -eq 0 -or $null -eq $adapters) {
                Write-Host "Nenhum adaptador de rede foi encontrado no sistema ou eles estão ocultos." -ForegroundColor Red
                $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
                return
            }
            
            # Mostrar lista enumerada com status em português
            Write-Host "Adaptadores de rede disponíveis:`n" -ForegroundColor Cyan
            for ($i = 0; $i -lt $adapters.Count; $i++) {
                $status = switch ($adapters[$i].Status) {
                    'Up'           { 'Conectado'; break }
                    'Disconnected' { 'Desconectado'; break }
                    'Disabled'     { 'Desativado'; break }
                    default        { $adapters[$i].Status }
                }
                
                $statusColor = if ($adapters[$i].Status -eq 'Up') { 'Green' } else { 'Red' }
                Write-Host "($($i+1)) $($adapters[$i].Name)" -NoNewline
                Write-Host " [$status]" -ForegroundColor $statusColor
            }
            
            # === ADICIONADA OPÇÃO DE VOLTAR AQUI ===
            Write-Host "(0) Voltar ao Menu Principal" -ForegroundColor Yellow
            
            # Solicitar seleção
            $selected = Read-Host "`nDigite o número da opção desejada"
            
            # Lógica atualizada para aceitar o 0 e validar erros
            if ($selected -eq '0') {
                return
            }
            elseif (-not ($selected -match '^\d+$') -or [int]$selected -lt 1 -or [int]$selected -gt $adapters.Count) {
                Write-Host "`nSeleção inválida. Tente novamente." -ForegroundColor Red
                Start-Sleep -Seconds 1
                Clear-Host
                Main-Selection
                return
            }
            
            $adapterName = $adapters[[int]$selected - 1].Name
            Show-AdapterSettings $adapterName

        } catch {
            Write-Host "`nOcorreu um erro ao tentar listar os adaptadores de rede." -ForegroundColor Red
            Write-Host "Detalhes: $_" -ForegroundColor DarkGray
            $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
        }
    }

    # Ponto de entrada principal
    if (-not [string]::IsNullOrEmpty($SelectedAdapter)) {
        Show-AdapterSettings $SelectedAdapter
    }
    else {
        Main-Selection
    }
}

# =====================================================================
# MENU PRINCIPAL
# =====================================================================
$menuLoop = $true
[console]::CursorVisible = $true 

while ($menuLoop) {
    Clear-Host
    Write-Host "===================================================" -ForegroundColor Cyan
    Write-Host "            MENU DE FERRAMENTAS DE REDE            " -ForegroundColor Cyan
    Write-Host "===================================================" -ForegroundColor Cyan
    Write-Host "1. Renovar IP e Limpar DNS (ipconfig)"
    Write-Host "2. Resetar Configurações de Rede (netsh) [AVISO]"
    Write-Host "3. Calibrador Avançado de Limites de Rede (MTU)"
    Write-Host "4. Analisar Configurações Avançadas do Adaptador"
    Write-Host "0. Sair"
    Write-Host "===================================================" -ForegroundColor Cyan
    
    $escolha = Read-Host "Selecione uma opção"

    switch ($escolha) {
        '1' {
            $pacoteOpcao1 = @(
                [PSCustomObject]@{ Cmd = "ipconfig /flushdns"; Info = "Cache do Resolver DNS expurgado com sucesso." }
                [PSCustomObject]@{ Cmd = "ipconfig /release"; Info = "Concessão de DHCP liberada (IP devolvido ao gateway)." }
                [PSCustomObject]@{ Cmd = "ipconfig /renew"; Info = "Nova negociação DHCP concluída; endereço IP renovado." }
                [PSCustomObject]@{ Cmd = "ipconfig /registerdns"; Info = "Atualização forçada dos registros de host concluída." }
            )
            Executar-ComandoComInterface -Comandos $pacoteOpcao1
            Write-Host "`n[+] Processo ipconfig finalizado." -ForegroundColor Green
            [console]::CursorVisible = $false
            Write-Host "[ENTER] Voltar ao Menu Principal" -ForegroundColor Cyan
            $null = [console]::ReadKey($true)
            [console]::CursorVisible = $true
        }
        '2' {
            Clear-Host
            Write-Host "[AVISO] Esta opção altera e reseta as configurações persistentes e o registro de rede do sistema." -ForegroundColor Yellow
            $confirmacao = Read-Host "Tem certeza de que deseja executar os comandos netsh? (S/N)"

            if ($confirmacao -match '^[Ss]') {
                $pacoteOpcao2 = @(
                    [PSCustomObject]@{ Cmd = "netsh winsock reset"; Info = "A ponte de conexão (Winsock) foi redefinida, removendo filtros de terceiros." }
                    [PSCustomObject]@{ Cmd = "netsh int ip reset"; Info = "O protocolo TCP/IP foi restaurado para as regras originais de fábrica." }
                    [PSCustomObject]@{ Cmd = "netsh winhttp reset proxy"; Info = "Qualquer configuração de proxy estática ou invisível foi removida." }
                )
                Executar-ComandoComInterface -Comandos $pacoteOpcao2
                Write-Host "`n[+] Processo netsh finalizado." -ForegroundColor Green
                
                $reiniciar = Read-Host "`n[?] Deseja reiniciar o computador agora para aplicar as alterações? (S/N)"
                if ($reiniciar -match '^[Ss]') {
                    Write-Host "`n[+] Reiniciando o computador..." -ForegroundColor Green
                    Restart-Computer -Force
                }
                [console]::CursorVisible = $false
                Write-Host "[ENTER] Voltar ao Menu Principal" -ForegroundColor Cyan
                $null = [console]::ReadKey($true)
                [console]::CursorVisible = $true
            } else {
                Write-Host "`n[-] Operação cancelada pelo usuário." -ForegroundColor Red
                [console]::CursorVisible = $false
                Write-Host "[ENTER] Voltar ao Menu Principal" -ForegroundColor Cyan
                $null = [console]::ReadKey($true)
                [console]::CursorVisible = $true
            }
        }
        '3' {
            Executar-CalibradorMTU
        }
        '4' {
            Clear-Host
            Show-NetworkAdapterConfig
        }
        '0' {
            $menuLoop = $false
            Write-Host "`nSaindo..."
        }
        default {
            Write-Host "`n[-] Opção inválida. Tente novamente." -ForegroundColor Red
            Start-Sleep -Seconds 2
        }
    }
}