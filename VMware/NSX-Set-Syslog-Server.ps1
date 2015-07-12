# This script sets the syslog server across the NSX components:
#  - NSX Manager
#  - NSX Edges Services Gateways
#  - NSX Controllers
#
# Martijn Smit <martijn@lostdomain.org>

$NSX_Manager_IP = "nsxmanager.myurl.nl"
$NSX_Manager_User = "admin"
$NSX_Manager_Password = "mysecretnsxpassword"

$LOG_Server = "10.0.0.10"
$LOG_Port = "514"

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

# Create authorization string for NSX Manager
$auth    = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($NSX_Manager_User + ":" + $NSX_Manager_Password))
$headers = @{ Authorization = "Basic $auth" }

# Set syslog server on NSX Manager
Write-Host "Configuring syslog server on NSX Manager.."
# Format API call
$requestBody  = '<?xml version="1.0" encoding="UTF-8"?>'
$requestBody += "<syslogserver>"
$requestBody += "<syslogServer>$LOG_Server</syslogServer>"
$requestBody += "<port>$LOG_Port</port>"
$requestBody += "<protocol>UDP</protocol>"
$requestBody += "</syslogserver>"
Http-Web-Request "PUT" "application/xml" "https://$NSX_Manager_IP" "/api/1.0/appliance-management/system/syslogserver" $headers $requestBody

# Set syslog server on NSX Edges
Write-Host "Getting a list of NSX Edges to configure syslog server on.."
# Get a list of all NSX Edges in the network
$result = Http-Web-Request "GET" "application/xml" "https://$NSX_Manager_IP" "/api/4.0/edges/" $headers ""
# Convert result text XML to a XML object which we can walk through
[xml]$result_xml = $result
# Walk through the edgeSummary list where all the NSX Edges are
foreach ($edge in $result_xml.pagedEdgeList.edgePage.edgeSummary)
{
	Write-Host "Setting syslog server for Edge:" $edge.name "with id:" $edge.id "and of type:" $edge.edgeType
	# Format API call
	$requestBody  = '<?xml version="1.0" encoding="UTF-8"?>'
	$requestBody += "<syslog>"
	$requestBody += " <protocol>UDP</protocol>"
	$requestBody += " <enabled>true</enabled>"
	$requestBody += " <serverAddresses>"
	$requestBody += "  <ipAddress>$LOG_Server</ipAddress>"
	$requestBody += " </serverAddresses>"
	$requestBody += "</syslog>"

	# Convert XML id to string for use in API URL
	[string]$edge_id = $edge.id
	# Set syslog server on NSX Edge
	$result = Http-Web-Request "GET" "application/xml" "https://$NSX_Manager_IP" "/api/4.0/edges/$edge_id/syslog/config" $headers "" #$requestBody
}

# Set syslog server on NSX Controllers

# Get a list of all controllers
Write-Host "Getting a list of NSX Controllers to configure syslog server on.."
$result = Http-Web-Request "GET" "application/xml" "https://$NSX_Manager_IP" "/api/2.0/vdn/controller" $headers ""
# Convert result text XML to a XML object which we can walk through
[xml]$result_xml = $result

foreach ($controller in $result_xml.controllers.controller)
{
	$requestBody  = '<?xml version="1.0" encoding="UTF-8"?>';
	$requestBody += "<controllerSyslogServer>";
	$requestBody += " <protocol>UDP</protocol>";
	$requestBody += " <level>INFO</level>";
	$requestBody += " <port>$LOG_Port</port>";
	$requestBody += " <syslogServer>$LOG_Server</syslogServer>";
	$requestBody += "</controllerSyslogServer>";

	# Convert XML id to string for use in API URL
	[string]$controller_id = $controller.id
	# Set syslog server on NSX Edge
	Write-Host "Setting syslog server for controller:" $controller_id
	$result = Http-Web-Request "POST" "application/xml" "https://$NSX_Manager_IP" "/api/2.0/vdn/controller/$controller_id/syslog" $headers "" #$requestBody
}

Write-Host "All done!"
