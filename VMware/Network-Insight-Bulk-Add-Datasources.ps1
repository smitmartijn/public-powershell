param (
  [parameter(Mandatory=$true, ValueFromPipeLine=$true, ValueFromPipeLineByPropertyName=$true)]
  [ValidateNotNullOrEmpty()]
  [string]$NI_IP,
  [parameter(Mandatory=$true, ValueFromPipeLine=$true, ValueFromPipeLineByPropertyName=$true)]
  [ValidateNotNullOrEmpty()]
  [string]$NI_Username,
  [parameter(Mandatory=$true, ValueFromPipeLine=$true, ValueFromPipeLineByPropertyName=$true)]
  [ValidateNotNullOrEmpty()]
  [string]$NI_Password,
  [parameter(Mandatory=$true, ValueFromPipeLine=$true, ValueFromPipeLineByPropertyName=$true)]
  [ValidateNotNullOrEmpty()]
  [string]$DatasourcesCSV
)

# Load PowerCLI

# Test CSV existance
if (!(Test-Path $DatasourcesCSV)) {
  Write-Host "[$(Get-Date)] CSV with data sources not found! ($DatasourcesCSV)" -ForegroundColor "red"
  Exit
}

# Ignore SSL certificate errors
[System.Net.ServicePointManager]::ServerCertificateValidationCallback = {$true}

# This function logs into Network Insight and keeps the cookie that's returned
function loginNetworkInsight([string]$Platform_VM_IP, [string]$Username, [string]$Password)
{
  $POST_Data = @{
    username = $Username
    password = $Password
  }
  $json = $POST_Data | ConvertTo-Json

  try {
    $response = Invoke-RestMethod "https://$Platform_VM_IP/api/auth/login" -Method POST -Body $json -ContentType 'application/json' -SessionVariable webSessionJar
    $global:webSessionJar = $webSessionJar
  }
  catch
  {
    if($_.Exception.Response.StatusCode.value__ -ne 200) {
      Write-Host "[$(Get-Date)] Unable to login to Network Insight!" -ForegroundColor "red"
      $_.Exception
    }
    else
    {
      if($response.message -ne "Logged in") {
        Write-Host "[$(Get-Date)] Unable to login with given credentials! Details: $response.message" -ForegroundColor "red"
        Exit
      }
    }
  }
  if($response.responseMessage -ne "Logged in") {
    Write-Host "[$(Get-Date)] Unable to login with given credentials! Details: $response.responseMessage" -ForegroundColor "red"
    Exit
  }
  else {
    Write-Host "[$(Get-Date)] Logged into Network Insight!" -ForegroundColor "green"
  }
}

# This function gets a list of installed Network Insight nodes and picks out the proxy VM ID and returns it
# Note: this returns the first proxy VM it encounters. If you have multiple proxies, this script will not load balance.
function getProxyNodeID([string]$Platform_VM_IP)
{
  try {
    $response = Invoke-RestMethod "https://$Platform_VM_IP/api/management/nodes" -Method GET -ContentType 'application/json' -WebSession $global:webSessionJar 
  }
  catch
  {
    if($_.Exception.Response.StatusCode.value__ -ne 200) {
      Write-Host "[$(Get-Date)] Unable to get the Proxy Node ID - can't continue!" -ForegroundColor "red"
      $_.Exception
      return "0";
    }
  }
  
  foreach($node in $response)
  {
    $nodeId = $node.nodeId
    $nodeType = $node.nodeType
	
    if($nodeType -eq "PROXY_VM") {
      return $nodeId
    }
  }
  
  return "0"
}

# Got this from the vRNI JS code
function getURLKeyByDatasource([string]$dataSourceType, [string]$prefix)
{

  if ($dataSourceType -eq "NSXCONTROLLER" -OR $dataSourceType -eq "CISCOCATALYST3750" -OR $dataSourceType -eq "CISCOCATALYST4500" -OR $dataSourceType -eq "CISCOCATALYST6500" -OR 
      $dataSourceType -eq "EDGE" -OR $dataSourceType -eq "CISCON1K" -OR $dataSourceType -eq "CISCON5K" -OR $dataSourceType -eq "CISCON7K" -OR $dataSourceType -eq "CISCON9K" -OR 
      $dataSourceType -eq "ARISTASWITCH" -OR $dataSourceType -eq "BROCADESWITCH" -OR $dataSourceType -eq "JUNIPERSWITCH" -OR $dataSourceType -eq "DELLSWITCH" -OR
      $dataSourceType -eq "HPC" -OR $dataSourceType -eq "DELLCHASSIS" -OR $dataSourceType -eq "FORCE10MXL10" -OR $dataSourceType -eq "FORCE10S6K" -OR $dataSourceType -eq "CISCOUCSFI" -OR
      $dataSourceType -eq "SPLUNK" -OR $dataSourceType -eq "GENERICSWITCH" -OR $dataSourceType -eq "GENERICCHASSIS" -OR $dataSourceType -eq "HPVIRTUALCONNECT") 
  {
    if ($prefix -eq "") {
      return "HOST"
    }
    return "$($prefix)_HOST"
  }
  else {
    return  "$($prefix)_URL"
  }
}
# Got this from the vRNI JS code as well
function getPrefixbyDataSource([string]$datasource) 
{
  if($datasource -eq "VCENTER") { return "VC" }
  elseif($datasource -eq "NSX") { return "NSX" }
  elseif($datasource -eq "PAN") { return "PAN" }
  elseif($datasource -eq "CISCOACI") { return "ACI" }
  elseif($datasource -eq "NSXCONTROLLER") { return "NSX" }
  elseif($datasource -eq "EDGE") { return "Edge" }
  elseif($datasource -eq "CISCOCATALYST4500") { return "Catalyst4500" }
  elseif($datasource -eq "CISCOUCS") { return "UCS" }
  elseif($datasource -eq "CISCON5K") { return "N5K" }
  elseif($datasource -eq "CISCON7K") { return "N7K" }
  elseif($datasource -eq "CISCOUCSFI") { return "UCSFI" }
  else { return "" }
}
# Got this from the vRNI JS code as well
function getUserKeyByDataSource([string]$prefix)
{
  if ($prefix -eq "") {
    return "USER";
  }
  return  "$($prefix)_USER"
}
# Got this from the vRNI JS code as well
function getPasswordkeyByDataSource([string]$prefix)
{
  if ($prefix -eq "") {
    return "PWD";
  }
  return  "$($prefix)_PWD"
}

# This function does the API call to add a data source
# We'll go through some data source type detection and add values based on the type (VC, NSX, CISCONx, etc)
function addDataSource([string]$dataSourceType, [string]$proxyNodeID, [string]$deviceIP, [string]$username, [string]$password, [string]$nickname, [string]$NSX_VC_URL, [string]$NSX_Controller_PW, [string]$Enable_SNMP)
{
  $prefix = getPrefixbyDataSource($dataSourceType)

  $request = @{
    dataSource = $dataSourceType
    keyValueList = @(
      @{key = "_collectorId"; value = $proxyNodeID; setKey = $True; setValue = $True }
    )
  }
  
  if($dataSourceType -eq "VCENTER") {
    $request.keyValueList += @{key = "ENABLE_IPFIX"; value = $True; setKey = $True; setValue = $True }
    # This enabled Netflow on all dvSwitches, it does not cherrypick 
    $request.keyValueList += @{key = "MANAGE_ALL_DVS"; value = $True; setKey = $True; setValue = $True }
  }
  else {
    # No Netflow on other types then vCenter
    $request.keyValueList += @{key = "ENABLE_IPFIX"; value = $False; setKey = $True; setValue = $True }
  }
  
  # Put the URL/IP, & login credentials into the request
  $request.keyValueList += @{key = (getURLKeyByDatasource $dataSourceType $prefix); value = $deviceIP; setKey = $True; setValue = $True }
  $request.keyValueList += @{key = (getUserKeyByDataSource $prefix); value = $username; setKey = $True; setValue = $True }
  $request.keyValueList += @{key = (getPasswordkeyByDataSource $prefix); value = $password; setKey = $True; setValue = $True }
  $request.keyValueList += @{key = "nickName"; value = $nickname; setKey = $True; setValue = $True }
  
  # If the data source has SNMP enabled, put the SNMP variables in the request
  if($Enable_SNMP -eq "yes") 
  {
    # TODO: figure out SNMP settings
    #$request.keyValueList += @{key = "_snmp_metric_enabled"; value = $True; setKey = $True; setValue = $True }
    #$request.keyValueList += @{key = "_snmp_host"; value = $deviceIP; setKey = $True; setValue = $True }
    #$request.keyValueList += @{key = "_snmp_version"; value = $deviceIP; setKey = $True; setValue = $True }
    #$request.keyValueList += @{key = "_snmp_sec_name"; value = $deviceIP; setKey = $True; setValue = $True }
    #$request.keyValueList += @{key = "_snmp_context_name"; value = $deviceIP; setKey = $True; setValue = $True }
    #$request.keyValueList += @{key = "_snmp_auth_type"; value = $deviceIP; setKey = $True; setValue = $True }
    #$request.keyValueList += @{key = "_snmp_auth_pass"; value = $deviceIP; setKey = $True; setValue = $True }
    #$request.keyValueList += @{key = "_snmp_priv_pass"; value = $deviceIP; setKey = $True; setValue = $True }
    #$request.keyValueList += @{key = "_snmp_priv_type"; value = $deviceIP; setKey = $True; setValue = $True }
    #$request.keyValueList += @{key = "_snmp_community"; value = $deviceIP; setKey = $True; setValue = $True }
  }
  #else {
    $request.keyValueList += @{key = "_snmp_metric_enabled"; value = $False; setKey = $True; setValue = $True }
  #}
  
  
  # with NSX, we have a few other options, like vCenter URL, Controller & Edge population
  if($dataSourceType -eq "NSX") 
  {
    # vCenter URL
    $request.keyValueList += @{key = "VC_URL"; value = $NSX_VC_URL; setKey = $True; setValue = $True }
    # TODO: make NSX controller population optional
    $request.keyValueList += @{key = "ENABLE_NSX_CONTROLLER"; value = $True; setKey = $True; setValue = $True }
    $request.keyValueList += @{key = "NSX_CONTROLLER_PWD"; value = $NSX_Controller_PW; setKey = $True; setValue = $True }
    
    # TODO: add some options for the NSX Edge population, now default to all and Central CLI
    $request.keyValueList += @{key = "ENABLE_AUTO_EDGES"; value = $True; setKey = $True; setValue = $True }
    $request.keyValueList += @{key = "USE_CENTRAL_CLI"; value = $True; setKey = $True; setValue = $True }
  }
  else 
  {
    # not a NSX data source? Disable all NSX options
    $request.keyValueList += @{key = "ENABLE_NSX_CONTROLLER"; value = $False; setKey = $True; setValue = $True }
    $request.keyValueList += @{key = "ENABLE_AUTO_EDGES"; value = $False; setKey = $True; setValue = $True }
    $request.keyValueList += @{key = "ENABLE_NSX_FLOW"; value = $False; setKey = $True; setValue = $True }
  }
  
  # we're adding the notes field, but no support in the CSV - so keep this empty for now
  $request.keyValueList += @{key = "notes"; value = ""; setKey = $True; setValue = $True}
  
  # convert the array to JSON format
  $request = ConvertTo-Json $request  
  
  # fire off the API call to the Network Insight private API
  try {
    $response = Invoke-RestMethod "https://$NI_IP/api/management/dataSource/setDataSource" -Method POST -Body $request -ContentType 'application/json' -WebSession $global:webSessionJar 
  }
  catch
  {
    if($_.Exception.Response.StatusCode.value__ -ne 200) {
      Write-Host "[$(Get-Date)] Adding Data Source failed!" -ForegroundColor "red"
      $_.Exception
    }
  }

  # errorCode 0 = good, anything other = bad
  if($response.errorCode -eq 0) {
    Write-Host "[$(Get-Date)] Added Data Source: $dataSourceType with host $deviceIP" -ForegroundColor "green"
  }
  else 
  {
    Write-Host "[$(Get-Date)] Unable to add Data Source: $($response.errorDetails) ($($response.errorCode))" -ForegroundColor "red"
    
    # Permission denied
    if($response.errorCode -eq -13) {
      Write-Host "[$(Get-Date)] Please check the credentials being used (username: $($response.username))" -ForegroundColor "red"
    }
  }
  
}

# Login to Network Insight first, so we get an authenticated cookie
loginNetworkInsight $NI_IP $NI_Username $NI_Password
# Then get the proxy VM internal ID, which we need to use when adding a data source
$proxyNodeID = (getProxyNodeID $NI_IP)

# Read 
$csvList = Import-CSV $DatasourcesCSV
foreach($csvLine in $csvList)
{
  # TODO: error checking & field content checks, 
  # also add a call to /api/management/dataSource/validateCredentials to validate data source before adding
  addDataSource $csvLine.DatasourceType $proxyNodeID $csvLine.IP $csvLine.Username $csvLine.Password $csvLine.Nickname $csvLine.NSX_VC_URL $csvLine.NSX_Controller_PW "no"
}

