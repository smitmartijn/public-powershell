

# This is where we save the cookies!
$global:CookieJar = New-Object System.Net.CookieContainer
$global:LoggedIn  = $False
$global:LoggingIn = $False

function ACI-API-Call([string]$method, [string]$encoding, [string]$url, $headers, [string]$postData)
{
  $return_value = New-Object PsObject -Property @{httpCode = ""; httpResponse = ""}

  ## Create the request
  [System.Net.HttpWebRequest] $request = [System.Net.HttpWebRequest] [System.Net.WebRequest]::Create($url)

  # Ignore SSL certificate errors
  [System.Net.ServicePointManager]::ServerCertificateValidationCallback = {$true}
  [System.Net.ServicePointManager]::SecurityProtocol = 3072 # <-- ACI NEEDS THIS!!

  # We want cookies!
  $request.CookieContainer = $global:CookieJar

  ## Add the method (GET, POST, etc.)
  $request.Method = $method
  ## Add an headers to the request
  foreach($key in $headers.keys)
  {
    $request.Headers.Add($key, $headers[$key])
  }

  # If we're logged in, add the saved cookies to this request
  if ($global:LoggedIn -eq $True) {
    $request.CookieContainer = $global:CookieJar
    $global:LoggingIn = $False
  }
  else
  {
    # We're not logged in to the APIC, start login first
    if($global:LoggingIn -eq $False)
    {
      $global:LoggingIn = $True
      ACI-Login $apic $username $password
    }
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

    foreach($cookie in $response.Cookies)
    {
      # We've found the APIC cookie and can conclude our login business
      if($cookie.Name -eq "APIC-cookie")
      {
        $global:LoggedIn = $True
        $global:LoggingIn = $False
      }
    }

    $sr = New-Object System.IO.StreamReader($response.GetResponseStream())
    $txt = $sr.ReadToEnd()
    ## NOTE: comment out the next line if you don't want this function to print to the terminal
    #Write-Host "CONTENT-TYPE: " $response.ContentType
    ## NOTE: comment out the next line if you don't want this function to print to the terminal
    #Write-Host "RAW RESPONSE DATA:" . $txt
    ## Return the response body to the caller
    $return_value.httpResponse = $txt
    $return_value.httpCode = [int]$response.StatusCode
    return $return_value
  }
  ## This catches errors from the server (404, 500, 501, etc.)
  catch [Net.WebException] {
    [System.Net.HttpWebResponse] $resp = [System.Net.HttpWebResponse] $_.Exception.Response
    ## NOTE: comment out the next line if you don't want this function to print to the terminal
    #Write-Host $resp.StatusCode -ForegroundColor Red -BackgroundColor Yellow
    ## NOTE: comment out the next line if you don't want this function to print to the terminal
    #Write-Host $resp.StatusDescription -ForegroundColor Red -BackgroundColor Yellow
    ## Return the error to the caller

    # if the APIC returns a 403, the session most likely has been expired. Login again and rerun the API call
    if($resp.StatusCode -eq 403)
    {
      # We do this by resetting the global login variables and simply call the ACI-API-Call function again
      $global:LoggedIn = $False
      $global:LoggingIn = $False
      ACI-API-Call $method $encoding $url $headers $postData
    }

    $return_value.httpResponse = $resp.StatusDescription
    $return_value.httpCode = [int]$resp.StatusCode
    return $return_value
  }
}

# Use this function to login to the APIC
function ACI-Login([string]$apic, [string]$username, [string]$password)
{
  # This is the URL we're going to be logging in to
  $loginurl = "https://" + $apic + "/api/aaaLogin.xml"
  # Format the XML body for a login
  $creds = '<aaaUser name="' + $username + '" pwd="' + $password + '"/>'
  # Execute the API Call
  $result = ACI-API-Call "POST" "application/xml" $loginurl "" $creds

  if($result.httpResponse.Contains("Unauthorized")) {
    Write-Host "Authentication to APIC failed!"
    Exit
  }
  else {
    Write-Host "Authenticated to the APIC!"
  }
}
