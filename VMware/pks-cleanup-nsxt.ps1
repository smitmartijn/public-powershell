# Edit this
$NSXT_Manager = "your-nsxt-manager-hostname-or-ip"
$NSXT_Username = "admin"
$NSXT_Password = 'mypassword'
# Stop editing

function Invoke-NSXTRestMethod
{
    param (
        [Parameter (Mandatory=$true)]
            [string]$Server,
        [Parameter (Mandatory=$true)]
            # REST Method (GET, POST, DELETE, UPDATE)
            [string]$Method,
        [Parameter (Mandatory=$true)]
            [string]$URI,
        [Parameter (Mandatory=$true)]
            [string]$Username,
        [Parameter (Mandatory=$true)]
            [string]$Password,
        [Parameter (Mandatory=$false)]
            [string]$Body = ""
    )


    $headerDict = @{}
    $headerDict.add("Content-Type", "application/json")
    $headerDict.add("X-Allow-Overwrite", "true")

    $cred = $Username + ":" + $Password
    $base64 = [System.Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes($cred))
    $headerDict.add("Authorization", "Basic " + $base64)

    $URL = "https://$($Server)$($URI)"
    Write-Debug "$(Get-Date -format s)  REST Call via Invoke-RestMethod: $Method $URL - with body: $Body"

    # Build up Invoke-RestMethod parameters, can differ per platform
    $invokeRestMethodParams = @{
        "Method" = $Method;
        "Headers" = $headerDict;
        "ContentType" = "application/json";
        "Uri" = $URL;
    }

    # If a body for a POST request has been specified, add it to the parameters for Invoke-RestMethod
    if($Body -ne "") {
        $invokeRestMethodParams.Add("Body", $body)
    }

    $invokeRestMethodParams.Add("SkipCertificateCheck", $true)

    # Energize!
    try
    {
        $response = Invoke-RestMethod @invokeRestMethodParams
    }

    # If its a webexception, we may have got a response from the server with more information...
    # Even if this happens on PoSH Core though, the ex is not a webexception and we cant get this info :(
    catch [System.Net.WebException] {
        #Check if there is a response populated in the response prop as we can return better detail.
        $response = $_.exception.response
        if ( $response ) {
            $responseStream = $response.GetResponseStream()
            $reader = New-Object system.io.streamreader($responseStream)
            $responseBody = $reader.readtoend()
            ## include ErrorDetails content in case therein lies juicy info
            $ErrorString = "$($MyInvocation.MyCommand.Name) : The API response received indicates a failure. $($response.StatusCode.value__) : $($response.StatusDescription) : Response Body: $($responseBody)`nErrorDetails: '$($_.ErrorDetails)'"

            # Log the error with response detail.
            Write-Warning -Message $ErrorString
            ## throw the actual error, so that the consumer can debug via the actuall ErrorRecord
            Throw $_
        }
        else
        {
            # No response, log and throw the underlying ex
            $ErrorString = "$($MyInvocation.MyCommand.Name) : Exception occured calling invoke-restmethod. $($_.exception.tostring())"
            Write-Warning -Message $_.exception.tostring()
            ## throw the actual error, so that the consumer can debug via the actuall ErrorRecord
            Throw $_
        }
    }

    catch {
        # Not a webexception (may be on PoSH core), log and throw the underlying ex string
        $ErrorString = "$($MyInvocation.MyCommand.Name) : Exception occured calling invoke-restmethod. $($_.exception.tostring())"
        Write-Warning -Message $ErrorString
        ## throw the actual error, so that the consumer can debug via the actuall ErrorRecord
        Throw $_
    }

    Write-Debug "$(Get-Date -format s) Invoke-RestMethod Result: $response"

    # Return result
    if($response) { $response }
}


function Confirm-Deletion
{
    param (
        [Parameter (Mandatory=$true)]
            [string]$Name
    )

    Write-Host "Do you want to delete '$Name'?"
    $input = Read-Host "Please write yes or no and press enter"

    switch ($input)
    {
        'yes' { return $true }
        'y' { return $true }
        'no' { return $false }
        'n' { return $false }
        default {
            Write-Host "You may only answer [yes|y] or [no|n], please try again."
            Confirm-Deletion -Name $Name
        }
    }
}


Write-Host -ForegroundColor yellow "Starting PKS Cleanup from NSX-T.."

$DEL_LS  = 0
$DEL_LR  = 0
$DEL_NS  = 0
$DEL_IPP = 0
$DEL_LB  = 0
$DEL_FW  = 0

Write-Host -ForegroundColor yellow "Starting with Logical Routers.."
$routers = Invoke-NSXTRestMethod -Username $NSXT_Username -Password $NSXT_Password -Server $NSXT_Manager -Method GET -URI "/api/v1/logical-routers"

foreach($router in $routers.results)
{
    if($router.display_name.StartsWith("pks-"))
    {
        if((Confirm-Deletion -Name $router.display_name) -eq $true) {
            Invoke-NSXTRestMethod -Username $NSXT_Username -Password $NSXT_Password -Server $NSXT_Manager -Method DELETE -URI "/api/v1/logical-routers/$($router.id)?force=true"
            $DEL_LR++
        }
        else {
            Write-Host "Skipping '$($router.display_name)'.."
        }
    }

}

Write-Host -ForegroundColor yellow "Moving on to Logical Switches.."
$switches = Invoke-NSXTRestMethod -Username $NSXT_Username -Password $NSXT_Password -Server $NSXT_Manager -Method GET -URI "/api/v1/logical-switches"

foreach($ls in $switches.results)
{
    if($ls.display_name.StartsWith("pks-"))
    {
        if((Confirm-Deletion -Name $ls.display_name) -eq $true) {
            Invoke-NSXTRestMethod -Username $NSXT_Username -Password $NSXT_Password -Server $NSXT_Manager -Method DELETE -URI "/api/v1/logical-switches/$($ls.id)?detach=true&cascade=true"
            $DEL_LS++
        }
        else {
            Write-Host "Skipping '$($ls.display_name)'.."
        }
    }
}


Write-Host -ForegroundColor yellow "Moving on to Firewall Sections.."
$sections = Invoke-NSXTRestMethod -Username $NSXT_Username -Password $NSXT_Password -Server $NSXT_Manager -Method GET -URI "/api/v1/firewall/sections"

foreach($sec in $sections.results)
{
    if($sec.display_name.Contains("pks-"))
    {
        if((Confirm-Deletion -Name $sec.display_name) -eq $true) {
            Invoke-NSXTRestMethod -Username $NSXT_Username -Password $NSXT_Password -Server $NSXT_Manager -Method DELETE -URI "/api/v1/firewall/sections/$($sec.id)?cascade=true"
            $DEL_FW++
        }
        else {
            Write-Host "Skipping '$($sec.display_name)'.."
        }
    }
}


Write-Host -ForegroundColor yellow "Moving on to Load Balancers.."
Write-Host -ForegroundColor yellow "Load Balancers Services.."
$loadbalancers = Invoke-NSXTRestMethod -Username $NSXT_Username -Password $NSXT_Password -Server $NSXT_Manager -Method GET -URI "/api/v1/loadbalancer/services"

foreach($lb in $loadbalancers.results)
{
    if($lb.display_name.StartsWith("pks-") -Or $lb.display_name.StartsWith("lb-pks-"))
    {
        if((Confirm-Deletion -Name $lb.display_name) -eq $true) {
            Invoke-NSXTRestMethod -Username $NSXT_Username -Password $NSXT_Password -Server $NSXT_Manager -Method DELETE -URI "/api/v1/loadbalancer/services/$($lb.id)"
            $DEL_LB++
        }
        else {
            Write-Host "Skipping '$($lb.display_name)'.."
        }
    }
}

Write-Host -ForegroundColor yellow "Load Balancers Virtual Servers.."
$loadbalancers = Invoke-NSXTRestMethod -Username $NSXT_Username -Password $NSXT_Password -Server $NSXT_Manager -Method GET -URI "/api/v1/loadbalancer/virtual-servers"

foreach($lb in $loadbalancers.results)
{
    if($lb.display_name.StartsWith("pks-") -Or $lb.display_name.StartsWith("lb-pks-"))
    {
        if((Confirm-Deletion -Name $lb.display_name) -eq $true) {
            Invoke-NSXTRestMethod -Username $NSXT_Username -Password $NSXT_Password -Server $NSXT_Manager -Method DELETE -URI "/api/v1/loadbalancer/virtual-servers/$($lb.id)"
            $DEL_LB++
        }
        else {
            Write-Host "Skipping '$($lb.display_name)'.."
        }
    }
}

Write-Host -ForegroundColor yellow "Load Balancers Pools.."
$loadbalancers = Invoke-NSXTRestMethod -Username $NSXT_Username -Password $NSXT_Password -Server $NSXT_Manager -Method GET -URI "/api/v1/loadbalancer/pools"

foreach($lb in $loadbalancers.results)
{
    if($lb.display_name.StartsWith("pks-") -Or $lb.display_name.StartsWith("lb-pks-"))
    {
        if((Confirm-Deletion -Name $lb.display_name) -eq $true) {
            Invoke-NSXTRestMethod -Username $NSXT_Username -Password $NSXT_Password -Server $NSXT_Manager -Method DELETE -URI "/api/v1/loadbalancer/pools/$($lb.id)"
            $DEL_LB++
        }
        else {
            Write-Host "Skipping '$($lb.display_name)'.."
        }
    }
}

Write-Host -ForegroundColor yellow "Load Balancers Monitors.."
$loadbalancers = Invoke-NSXTRestMethod -Username $NSXT_Username -Password $NSXT_Password -Server $NSXT_Manager -Method GET -URI "/api/v1/loadbalancer/monitors"

foreach($lb in $loadbalancers.results)
{
    if($lb.display_name.StartsWith("pks-") -Or $lb.display_name.StartsWith("lb-pks-"))
    {
        if((Confirm-Deletion -Name $lb.display_name) -eq $true) {
            Invoke-NSXTRestMethod -Username $NSXT_Username -Password $NSXT_Password -Server $NSXT_Manager -Method DELETE -URI "/api/v1/loadbalancer/monitors/$($lb.id)"
            $DEL_LB++
        }
        else {
            Write-Host "Skipping '$($lb.display_name)'.."
        }
    }
}


Write-Host -ForegroundColor yellow "Moving on to NS Groups.."
$nsgroups = Invoke-NSXTRestMethod -Username $NSXT_Username -Password $NSXT_Password -Server $NSXT_Manager -Method GET -URI "/api/v1/ns-groups"

foreach($group in $nsgroups.results)
{
    if($group.display_name.StartsWith("pks-") -Or $group.display_name.StartsWith("lb-pks-"))
    {
        if((Confirm-Deletion -Name $group.display_name) -eq $true) {
            Invoke-NSXTRestMethod -Username $NSXT_Username -Password $NSXT_Password -Server $NSXT_Manager -Method DELETE -URI "/api/v1/ns-groups/$($group.id)?force=true"
            $DEL_NS++
        }
        else {
            Write-Host "Skipping '$($group.display_name)'.."
        }
    }
}

Write-Host -ForegroundColor yellow "Moving on to IP Pools.."
$ippools = Invoke-NSXTRestMethod -Username $NSXT_Username -Password $NSXT_Password -Server $NSXT_Manager -Method GET -URI "/api/v1/pools/ip-pools"

foreach($pool in $ippools.results)
{
    if($pool.display_name.StartsWith("pks-") -Or $pool.display_name.StartsWith("lb-pks-"))
    {
        if((Confirm-Deletion -Name $pool.display_name) -eq $true) {
            Invoke-NSXTRestMethod -Username $NSXT_Username -Password $NSXT_Password -Server $NSXT_Manager -Method DELETE -URI "/api/v1/pools/ip-pools/$($pool.id)?force=true"
            $DEL_IPP++
        }
        else {
            Write-Host "Skipping '$($pool.display_name)'.."
        }
    }
}



Write-Host -ForegroundColor green "Done!"
Write-Host "Deleted:"
Write-Host "Logical Routers: $DEL_LR"
Write-Host "Logical Switches: $DEL_LS"
Write-Host "Firewall Sections: $DEL_FW"
Write-Host "NS Groups: $DEL_NS"
Write-Host "IP Pools: $DEL_IPP"
Write-Host "Load Balancer Objects: $DEL_LB"

