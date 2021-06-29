FROM mcr.microsoft.com/powershell:7.1.1-windowsservercore-2004 as base
SHELL [ "pwsh", "-Command" ]
RUN $ProgressPreference = 'SilentlyContinue' ; \
  Write-Host '--- Download Datagateway installer ---' ; \
  Invoke-WebRequest -Uri 'https://go.microsoft.com/fwlink/?LinkID=820931' -OutFile ./GatewayInstall.exe ; \
  Write-Host '--- Start Datagateway installation ---' ; \
  Install-Module -Name DataGateway -Force -Scope AllUsers ; \
  Import-Module DataGateway -Force ; \
  $gwInstall = Start-Process -Filepath .\GatewayInstall.exe -ArgumentList /s -PassThru ; \
  do { \
  Write-Host 'Wait for installation to finish...' ; \
  $log = Get-CimInstance -ClassName Win32_NTLogEvent -Filter 'LogFile=\"application\" and EventIdentifier=\"1033\" and SourceName=\"MSIInstaller\"' ; \
  Start-Sleep -Seconds 5 \
  } until ($log.count -ge 2)  ; \
  Get-Process -ProcessName $gwInstall.ProcessName | Stop-Process -Force ; \
  Write-Host '--- Setting Datagateway service to use localsystem login ---' ; \
  $null = Stop-Service -Name 'PBIEgwService' ; \
  $service = Get-CimInstance 'win32_service' -Filter 'name=\"PBIEgwService\"' ; \
  $null = $service | Invoke-CimMethod -Name Change -Arguments @{StartName='LocalSystem'} ; \
  Write-Host '--- Finished Datagateway installation ---' ; \
  Remove-Item -Path ./GatewayInstall.exe -Force

FROM base
SHELL [ "pwsh", "-Command" ]
ARG AppId
ARG AppSecret
ARG TenantId
ARG GatewayUserObjectId
ARG ClusterName
ENV AppId=${AppId}
ENV AppSecret=${AppSecret}
ENV TenantId=${TenantId}
ENV GatewayUserObjectId=${GatewayUserObjectId}
ENV ClusterName=${ClusterName}

COPY entrypoint.ps1 .

RUN 'AppId', 'AppSecret', 'TenantId', 'GatewayUserObjectId', 'ClusterName' | \
  ForEach-Object -Process { \
  $envValue = [System.Environment]::GetEnvironmentVariable($_) ; \
  if ([string]::IsNullOrEmpty($envValue)) { \
  throw "Missing Docker ARG: $_" \
  } ; \
  } ; \
  Write-Host '--- Connecting with Service Account ---' ; \
  $clientSecret = ConvertTo-SecureString -AsPlainText -Force -String $env:AppSecret ; \
  Connect-DataGatewayServiceAccount -ApplicationId $env:AppId -ClientSecret $clientSecret -Tenant $env:TenantId ; \
  Write-Host '--- Creating Datagateway cluster ---' ; \
  $recoveryKey = ConvertTo-SecureString -AsPlainText -Force -String $env:TenantId ; \
  $cluster = Add-DataGatewayCluster -RecoveryKey $recoveryKey -GatewayName $env:ClusterName -OverwriteExistingGateway ; \
  Write-Host '--- Add Datagateway cluster Admin ---' ; \
  Add-DataGatewayClusterUser -GatewayClusterId $cluster.GatewayObjectId -PrincipalObjectId $env:GatewayUserObjectId -Role 'Admin' ; \
  start-Sleep -Seconds 10s

ENTRYPOINT [ "pwsh", "entrypoint.ps1" ]
