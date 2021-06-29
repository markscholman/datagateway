$ErrorActionPreference = 'Stop'
if ($env:APPSETTING_USE_FILESHARE -eq 1) {
  if ($null -eq $env:APPSETTING_FILESHARE_USER -or $null -eq $env:APPSETTING_FILESHARE_PASSWORD) {
    throw 'Fileshare credentials not specified in app settings. Please provide fileshare credentials or disable USE_FILESHARE'
  }
  Write-Host -Object 'Creating fileshare user'
  $fileSharePwd = (ConvertTo-SecureString -String "$env:APPSETTING_FILESHARE_PASSWORD" -AsPlainText -Force)
  New-LocalUser -Name $env:APPSETTING_FILESHARE_USER -Password $fileSharePwd -AccountNeverExpires -UserMayNotChangePassword
}

Connect-DataGatewayServiceAccount -ApplicationId $env:AppId -ClientSecret (ConvertTo-SecureString -AsPlainText -Force -String $env:AppSecret ) -Tenant $env:TenantId
$cluster = Get-DataGatewayCluster | Where-Object -FilterScript { $_.name -eq $env:ClusterName }

$sw = [System.Diagnostics.Stopwatch]::StartNew()
do {
  Write-Host -Object "Checking if Datagateway $env:ClusterName is Online..."
  Start-Sleep -Seconds 2
  $status = (Get-DataGatewayClusterStatus -GatewayClusterId $cluster.Id).ClusterStatus
} until ($status -eq 'Live' -or $sw.Elapsed -gt [timespan]::FromMinutes(2))

if ($status -ne 'Live') {
  Write-Host -Object 'Datagateway did not become Live, terminating'
  throw 'Datagateway did not become Live'
} else {
  Write-Host -Object 'Datagateway is live'
}

while (Get-Process -Name Microsoft.PowerBI.EnterpriseGateway) {
  Write-Host -Object "$([datetime]::UtcNow.ToString('yyyy-MM-dd HH:mm')) - Datagateway process is running..."
  Start-Sleep -Seconds 30
}

Write-Host -Object "Datagateway process has stopped, terminating"
throw 'Datagateway process has stopped'
