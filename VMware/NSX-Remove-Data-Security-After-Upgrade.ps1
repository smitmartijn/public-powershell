# This small script removes VMware Data Security from ESXi hosts
# via an API call - for after you've upgraded vCNS to NSX and
# forgot to uninstall Data Security
#
# Martijn Smit <martijn@lostdomain.org>

$vCenter_IP = "vcenter.myurl.nl"
$NSX_Manager_IP = "nsxmanager.myurl.nl"
$NSX_Manager_User = "admin"
$NSX_Manager_Password = "mysecretnsxpassword"

###### START CODE ######

# This function is from: http://sharpcodenotes.blogspot.nl/2013/03/how-to-make-http-request-with-powershell.html
function Http-Web-Request([string]$method,[string]$encoding,[string]$server,[string]$path,$headers,[string]$postData)
{
    ## Compose the URL and create the request
    $url = "$server/$path"
    [System.Net.HttpWebRequest] $request = [System.Net.HttpWebRequest] [System.Net.WebRequest]::Create($url)

	# Ignore SSL certificate errors
	[System.Net.ServicePointManager]::ServerCertificateValidationCallback = {$true}

    ## Add the method (GET, POST, etc.)
    $request.Method = $method
    ## Add an headers to the request
    foreach($key in $headers.keys)
    {
        $request.Headers.Add($key, $headers[$key])
    }

    ## We are using $encoding for the request as well as the expected response
    $request.Accept = $encoding
    ## Send a custom user agent if you want
    $request.UserAgent = "PowerShell script"

    ## Create the request body if the verb accepts it (NOTE: utf-8 is assumed here)
    if ($method -eq "POST" -or $method -eq "PUT") {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($postData)
        $request.ContentType = $encoding
        $request.ContentLength = $bytes.Length

        [System.IO.Stream] $outputStream = [System.IO.Stream]$request.GetRequestStream()
        $outputStream.Write($bytes,0,$bytes.Length)
        $outputStream.Close()
    }

    ## This is where we actually make the call.
    try
    {
        [System.Net.HttpWebResponse] $response = [System.Net.HttpWebResponse] $request.GetResponse()
        $sr = New-Object System.IO.StreamReader($response.GetResponseStream())
        $txt = $sr.ReadToEnd()
        ## NOTE: comment out the next line if you don't want this function to print to the terminal
        #Write-Host "CONTENT-TYPE: " $response.ContentType
        ## NOTE: comment out the next line if you don't want this function to print to the terminal
        #Write-Host "RAW RESPONSE DATA:" . $txt
        ## Return the response body to the caller
        return $txt
    }
    ## This catches errors from the server (404, 500, 501, etc.)
    catch [Net.WebException] {
        [System.Net.HttpWebResponse] $resp = [System.Net.HttpWebResponse] $_.Exception.Response
        ## NOTE: comment out the next line if you don't want this function to print to the terminal
        #Write-Host $resp.StatusCode -ForegroundColor Red -BackgroundColor Yellow
        ## NOTE: comment out the next line if you don't want this function to print to the terminal
        #Write-Host $resp.StatusDescription -ForegroundColor Red -BackgroundColor Yellow
        ## Return the error to the caller
        return $resp.StatusDescription
    }
}

# open vCenter connection
Connect-VIServer -Server $vCenter_IP

# Create authorization string for NSX Manager
$auth    = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($NSX_Manager_User + ":" + $NSX_Manager_Password))
$headers = @{ Authorization = "Basic $auth" }

# Get all the ESXi host ids first
$hosts = Get-VMHost | Select ID

# Loop through the ESXi host ids and execute API call for each of them
foreach($host_info in $hosts)
{
	# Get-VMHost is a little more verbose then we'd like it to be - remove the prepend "HostSystem-"
	$host_id = $host_info.Id -replace "^HostSystem\-", ""

	Write-Host "Removing Data Security from: $host_id"

	# Do API call
	$result = Http-Web-Request "DELETE" "application/xml" "https://$NSX_Manager_IP" "/api/1.0/vshield/$host_id/vsds" $headers ""

	Write-Host "Response from NSX Manager: $result"

}
