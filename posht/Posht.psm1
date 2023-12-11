#region variables

$Script:ApiSession = $null
$Script:ApiConfigFileName = "posht.json"
$Script:ApiConfigFolder = ".posht"
$Script:ApiTitleForegroundColor = [System.ConsoleColor]::Magenta
$Script:ApiTitleBackgroundColor = [System.ConsoleColor]::Black

#endregion

#region classes

class ApiRequest {
  [string]$Method
  [string]$BaseUri
  [string]$Path
  [System.Object]$Body
  [hashtable]$Headers
  [bool]$PersistSession

  ApiRequest($ApiRequestRaw) {
    # from json
    $this.Method = $ApiRequestRaw.Method
    $this.BaseUri = $ApiRequestRaw.BaseUri
    $this.Path = $ApiRequestRaw.Path
    $this.Body = $ApiRequestRaw.Body
    $this.PersistSession = $ApiRequestRaw.PersistSession
    $this.Headers = [ordered]@{}
    foreach ($Prop in $ApiRequestRaw.Headers.PSObject.Properties) {
      $this.Headers[$Prop.Name] = $Prop.Value
    }
  }

  ApiRequest([hashtable]$Headers, [string]$Method, [string]$Uri, [System.Object]$Body, [bool]$PersistSession) {
    # standard
    $UriObject = [Uri]::new($Uri)
    $this.Method = $Method
    $this.BaseUri = "$($UriObject.Scheme)://$($UriObject.Host):$($UriObject.Port)"
    $this.Path = $UriObject.PathAndQuery
    $this.Body = $Body
    $this.Headers = $Headers
    $this.PersistSession = $PersistSession
  }

  [string] GetUri() {
    return "$($this.BaseUri)$($this.Path)"
  }

  [string] ToString() {
    return "$($this.Method) $($this.BaseUri)$($this.Path)"
  }

  [string] GetCollectionKey() {
    return "$($this.Method)_$($this.Path)"
  }

  [string] GetKey() {
    return "$($this.Method)_$($this.BaseUri)_$($this.Path)"
  }
}

class ApiCollection {
  [string]$BaseUri
  [hashtable]$Headers
  [hashtable]$Requests

  ApiCollection($ApiCollectionRaw) {
    # from json
    $this.BaseUri = $ApiCollectionRaw.BaseUri
    $this.Headers = [ordered]@{}
    foreach ($Prop in $ApiCollectionRaw.Headers.PSObject.Properties) {
      $this.Headers[$Prop.Name] = $Prop.Value
    }
    $this.Requests = [ordered]@{}
    foreach ($Prop in $ApiCollectionRaw.Requests.PSObject.Properties) {
      $this.Requests[$Prop.Name] = [ApiRequest]::new($Prop.Value)
    }
  }

  ApiCollection([string]$BaseUri, [hashtable]$Headers) {
    # standard
    $this.BaseUri = $BaseUri
    $this.Headers = $Headers
    $this.Requests = [hashtable]@{}
  }

  [string] ToString() {
    return $this.BaseUri
  }

  [string] GetKey() {
    return $this.BaseUri
  }
}

class ApiConfig {
  [string] $Id
  [hashtable] $DefaultHeaders
  [hashtable] $Collections
  [datetime] $LastUpdate

  ApiConfig() {
    # empty/new config
    $this.Id = (New-Guid).Guid
    $this.DefaultHeaders = [hashtable]@{
      "accept"        = "application/json"
      "content-type"  = "application/json"
      "Cache-Control" = "no-store"
    }
    $this.Collections = [hashtable]@{}
    $this.LastUpdate = Get-Date
  }

  ApiConfig($ApiConfigRaw) {
    # from json
    $this.Id = $ApiConfigRaw.Id
    if($null -eq $this.Id -or $this.Id -eq ""){
      $this.Id = (New-Guid).Guid
    }

    $this.DefaultHeaders = [hashtable]@{}
    foreach ($Prop in $ApiConfigRaw.DefaultHeaders.PSObject.Properties) {
      $this.DefaultHeaders[$Prop.Name] = $Prop.Value
    }

    $this.Collections = [hashtable]@{}
    foreach ($Prop in $ApiConfigRaw.Collections.PSObject.Properties) {
      $this.Collections[$Prop.Name] = [ApiCollection]::new($Prop.Value)
    }

    $this.LastUpdate = $ApiConfigRaw.LastUpdate
  }

  [void] AddRequest([ApiRequest]$Request) {
    $ExistingCollection = $this.Collections[$Request.BaseUri]

    if ($null -eq $ExistingCollection) {
      # create new collection and add request
      $Collection = [ApiCollection]::new($Request.BaseUri, $Request.Headers)
      $Collection.Requests[$Request.GetCollectionKey()] = $Request
      $this.Collections[$Request.BaseUri] = $Collection
    }
    else {
      # add/update request in existing collection
      $ExistingCollection.Requests[$Request.GetCollectionKey()] = $Request
    }
  }

  [string] CalculateBaseUri($FullUri) {
    $UriObject = [Uri]::new($FullUri)
    $BaseUri = "$($UriObject.Scheme)://$($UriObject.Host):$($UriObject.Port)"
    return $BaseUri
  }

  [hashtable] GetDefaultHeaders() {
    $DefaultHeadersClone = [hashtable]@{}
    foreach ($Kvp in $this.DefaultHeaders.GetEnumerator()) {
      $DefaultHeadersClone[$Kvp.Name] = $Kvp.Value
    }
    return $DefaultHeadersClone # cloned
  }
}

class CliMenuItem {
  [string]$Label
  [System.Object]$Data

  CliMenuItem([string]$Label, [System.object]$Data) {
    $this.Label = $Label
    $this.Data = $Data
  }

  [string] ToString() {
    return $this.Label
  }
}

#endregion

#region private functions

function Get-ApiSession {
  return $Script:ApiSession
}

function Set-ApiSession {
  [CmdletBinding()]
  param (
    [Parameter(Mandatory = $true)]
    [Microsoft.PowerShell.Commands.WebRequestSession]$Session
  )

  $Script:ApiSession = $Session
}

function Resolve-ApiConfigFilePath {
  $LocalPath = Get-ApiConfigFilePath -Source Local
  if (Test-Path -Path $LocalPath) {
    return $LocalPath
  }
  else {
    return (Get-ApiConfigFilePath -Source UserProfile)
  }
}

function Get-ApiConfigFilePath {
  [CmdletBinding()]
  param (
    [Parameter(Mandatory = $true)]
    [ValidateSet("Local", "UserProfile")]
    [string]$Source
  )

  switch ($Source) {
    "Local" {
      return (Join-Path -Path (Get-Location).Path -ChildPath $Script:ApiConfigFileName)
    }
    Default {
      return (Join-Path -Path $HOME -ChildPath $Script:ApiConfigFolder $Script:ApiConfigFileName)
    }
  }
}

function Get-ApiConfig {
  # No in memory api config at the moment (it is always read from file)
  return (Read-ApiConfig)
}

function Read-ApiConfig {
  $ConfigFilePath = Resolve-ApiConfigFilePath
  if (Test-Path -Path $ConfigFilePath) {
    Write-Verbose "Read ApiConfig from $ConfigFilePath"
    $ConfigFile = Get-Content -Path $ConfigFilePath -Raw

    $RawApiConfig = $ConfigFile | ConvertFrom-Json -Depth 10
    return [ApiConfig]::new($RawApiConfig)
  }
  else {
    # no config file found
    return (New-ApiConfig -Confirm:$false)
  }
}

function Save-ApiConfig {
  [CmdletBinding()]
  param (
    [Parameter(Mandatory = $true)]
    [ApiConfig]$ApiConfig,

    [Parameter(Mandatory = $false)]
    [string]$FullPath
  )

  if ($null -eq $ApiConfig) {
    return;
  }

  if ($null -eq $FullPath -or $FullPath -eq "") {
    $ConfigFilePath = Resolve-ApiConfigFilePath
  }
  else {
    $ConfigFilePath = $FullPath
  }

  $ApiConfig.LastUpdate = Get-Date
  $Directory = Split-Path -Path $ConfigFilePath -Parent
  if (-Not (Test-Path -Path $Directory)) {
    Write-Verbose "Create directory '$Directory'"
    New-Item -ItemType Directory -Path $Directory -Force | Out-Null
  }

  $ApiConfig | ConvertTo-Json -Depth 10 | Out-File -FilePath $ConfigFilePath
  Write-Verbose "ApiConfig saved to $ConfigFilePath with timestamp '$($ApiConfig.LastUpdate)'"
}

function ConvertTo-CliMenuItems {
  param (
    [Parameter(Mandatory = $true)]
    [array]$Items,

    [Parameter(Mandatory = $false)]
    [func[object, string]]$LabelFunction = $null
  )

  $MenuItems = [System.Collections.ArrayList]@()
  if (!$Items) {
    return $MenuItems
  }

  foreach ($Item in $Items) {
    if ($LabelFunction) {
      $Label = $LabelFunction.Invoke($Item)
      $MenuItems.Add([CliMenuItem]::new($Label, $Item)) | Out-Null
    }
    else {
      $MenuItems.Add([CliMenuItem]::new($Item.ToString(), $Item)) | Out-Null
    }
  }

  return [CliMenuItem[]]$MenuItems
}

function Build-CliMenu {
  param (
    [Parameter(Mandatory = $true)]
    [CliMenuItem[]]$Items,

    [Parameter(Mandatory = $true)]
    $MenuPosition,

    [Parameter(Mandatory = $true)]
    $Multiselect,

    [Parameter(Mandatory = $true)]
    $Selection
  )

  $ItemsLength = $Items.Count
  for ($i = 0; $i -le $ItemsLength; $i++) {
    if ($null -ne $Items[$i]) {
      $Item = $Items[$i]
      $Label = $Item.Label
      if ($Multiselect) {
        if ($Selection -contains $i) {
          $Label = '[x] ' + $Label
        }
        else {
          $Label = '[ ] ' + $Label
        }
      }
      if ($i -eq $MenuPosition) {

        Write-Host "> $Label" -ForegroundColor Green
      }
      else {
        Write-Host "  $Label"
      }
    }
  }
}

function Set-CliMenuSelection {
  param (
    [Parameter(Mandatory = $true)]
    [int]$Position,

    [Parameter(Mandatory = $true)]
    [array]$Selection
  )

  if ($Selection -contains $Position) { 
    $Result = $Selection | Where-Object { $_ -ne $Position }
  }
  else {
    $Selection += $Position
    $Result = $Selection
  }
  $Result
}

function Show-CliMenu {
  param (
    [Parameter(Mandatory = $true)]
    [CliMenuItem[]]$Items,

    [Parameter()]
    [switch]$ReturnIndex = $false,

    [Parameter()]
    [switch]$Multiselect = $false
  )

  $VKeyCode = 0
  $Position = 0
  $Selection = @()

  if ($Items.Count -gt 0) {
    try {
      [console]::CursorVisible = $false #prevents cursor flickering
      Build-CliMenu $Items $Position $Multiselect $Selection
      While ($VKeyCode -ne 13 -and $VKeyCode -ne 27) {
        $PressedKey = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        $VKeyCode = $PressedKey.VirtualKeyCode
        # 38=up-arrow,40=down-arrow,36=home,35=end,27=esc,13=enter
        if ($VKeyCode -eq 38 -or $PressedKey.Character -eq 'k') { $Position-- } #go up
        if ($VKeyCode -eq 40 -or $PressedKey.Character -eq 'j') { $Position++ } #go down
        if ($VKeyCode -eq 36) { $Position = 0 } #top
        if ($VKeyCode -eq 35) { $Position = $Items.Count - 1 } #bottom
        if ($PressedKey.Character -eq ' ') { $Selection = Set-CliMenuSelection $Position $Selection }
        if ($Position -lt 0) { $Position = 0 }
        if ($VKeyCode -eq 27) { $Position = $null }
        if ($Position -ge $Items.Count) { $Position = $Items.Count - 1 }
        if ($VKeyCode -ne 27) {
          $startPos = [System.Console]::CursorTop - $Items.Count
          [System.Console]::SetCursorPosition(0, $startPos)
          Build-CliMenu $Items $Position $Multiselect $Selection
        }
      }
    }
    finally {
      [System.Console]::SetCursorPosition(0, $startPos + $Items.Count)
      [console]::CursorVisible = $true
    }
  }
  else {
    $Position = $null
  }

  if ($ReturnIndex -eq $false -and $null -ne $Position) {
    if ($Multiselect) {
      return $Items[$Selection].Data # return of menu item here
    }
    else {
      return $Items[$Position].Data # return of menu item here
    }
  }
  else {
    if ($Multiselect) {
      return $Selection
    }
    else {
      return $Position
    }
  }
}

function Show-ApiTrademark {
 
  
  Write-Host "    ____             __    __     __                                  ___          " -ForegroundColor $Script:ApiTitleForegroundColor -BackgroundColor $Script:ApiTitleBackgroundColor
  Write-Host "   / __ \____  _____/ /_  / /_   / /_  __  __   __  _____  ____  ____/ (_)________ " -ForegroundColor $Script:ApiTitleForegroundColor -BackgroundColor $Script:ApiTitleBackgroundColor
  Write-Host "  / /_/ / __ \/ ___/ __ \/ __/  / __ \/ / / /  / / / / _ \/ __ \/ __  / / ___/ __ \" -ForegroundColor $Script:ApiTitleForegroundColor -BackgroundColor $Script:ApiTitleBackgroundColor
  Write-Host " / ____/ /_/ (__  ) / / / /_   / /_/ / /_/ /  / /_/ /  __/ / / / /_/ / / /__/ /_/ /" -ForegroundColor $Script:ApiTitleForegroundColor -BackgroundColor $Script:ApiTitleBackgroundColor
  Write-Host "/_/    \____/____/_/ /_/\__/  /_.___/\__, /   \__, /\___/_/ /_/\__,_/_/\___/\____/ " -ForegroundColor $Script:ApiTitleForegroundColor -BackgroundColor $Script:ApiTitleBackgroundColor
  Write-Host "                                    /____/   /____/                                " -ForegroundColor $Script:ApiTitleForegroundColor -BackgroundColor $Script:ApiTitleBackgroundColor
  Write-Host "                                                                                   " -ForegroundColor $Script:ApiTitleForegroundColor -BackgroundColor $Script:ApiTitleBackgroundColor
  Write-Host ""
}

function Write-ApiHeader {
  param (
    [Parameter(Mandatory = $true)]
    [string]$Title
  )

  $Length = $Title.Length
  Write-Host $Title
  Write-Host ("-" * $Length)
}

function ToFixedLength {
  param (
    [Parameter(Mandatory = $true)]
    [string]$Text,

    [Parameter(Mandatory = $true)]
    [int]$Length
  )

  if ($Text.Length -ge $Length) {
    return $Text.Substring(0, $Length)
  }

  return $Text + (" " * ($Length - $Text.Length))
}

function CollectionUriArgCompleter {
  param ( $commandName,
    $parameterName,
    $wordToComplete,
    $commandAst,
    $fakeBoundParameters )

  # NOTE: can only use exported functions here!!!
  $Collections = Get-ApiCollection
  $Collections | Where-Object { $_.BaseUri -like "$wordToComplete*" } | ForEach-Object { $_.BaseUri }
}

function RequestUriArgCompleter {
  param ( $commandName,
    $parameterName,
    $wordToComplete,
    $commandAst,
    $fakeBoundParameters )

  # NOTE: can only use exported functions here!!!
  $Requests = Get-ApiRequest
  $Requests | Where-Object { $_.GetUri() -like "$wordToComplete*" } | ForEach-Object { $_.GetUri() }
}

function HashtableToString {
  param ( 
    [hashtable]$Hashtable
  )

  if ($null -eq $Hashtable) {
    return "";
  }
  
  $Result = ""

  $Hashtable.Keys | ForEach-Object { $Result += "$_=$($Hashtable[$_])," }
  return $Result
}

#endregion

#region public functions

<#
.SYNOPSIS
Creates a new posht config/request file (posht.json)

.DESCRIPTION
Creates a new posht config/request file (posht.json)
If the local switch is not specified, file is saved in the user profile path

.PARAMETER Local
Create and save at current path (instead of user profile path)

.EXAMPLE
New-ApiConfig
New-ApiConfig -Local

#>
function New-ApiConfig {
  [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
  param (
    [Parameter(Mandatory = $false)]
    [switch]$Local
  )

  $FullPath = ""
  if($Local){
    $FullPath = Get-ApiConfigFilePath -Source Local
  } else {
    $FullPath = Get-ApiConfigFilePath -Source UserProfile 
  }

  if ($PSCmdlet.ShouldProcess("This will create a new config file under '$FullPath'. If there is an existing one, it will be overwritten!", $FullPath, 'Initialize new config file (may overwrite exting one)?')) {
    $ApiConfig = [ApiConfig]::new()
    Write-Verbose "New ApiConfig initialized"

    Save-ApiConfig -ApiConfig $ApiConfig -FullPath $FullPath
    return $ApiConfig
  }
}

function Clear-ApiSession {
  $Script:ApiSession = $null
}

<#
.SYNOPSIS
Get an array of collections (One collection contains multiple requests)

.DESCRIPTION
Get collection of requests (grouped by BaseUri)

.PARAMETER BaseUri
Filter by BaseUri (wildcards are allowed)

.EXAMPLE
Get-ApiCollection
Get-ApiCollection -BaseUri "http://localhost*"
Get-ApiCollection -BaseUri "https*"

.NOTES
#>
function Get-ApiCollection {
  [CmdletBinding()]
  param (
    [Parameter()]
    [string]$BaseUri
  )

  $ApiConfig = Get-ApiConfig

  if ($BaseUri) {
    $Collections = [System.Collections.ArrayList]@()
    foreach ($Collection in $ApiConfig.Collections.Values) {
      if ($Collection.BaseUri -like $BaseUri) {
        $Collections.Add($Collection) | Out-Null
      }
    }
    return $Collections
  }
  else {
    return $ApiConfig.Collections.Values
  }
}
Register-ArgumentCompleter -CommandName Get-ApiCollection -ParameterName BaseUri -ScriptBlock { CollectionUriArgCompleter @args }

<#
.SYNOPSIS
Get an array of requets

.DESCRIPTION
Get an array of requets

.PARAMETER BaseUri
Filter requests by BaseUri (wildcards allowed)

.PARAMETER Method
Filter requests by http method (wildcards allowed)

.EXAMPLE
Get-ApiRequest
Get-ApiRequest -BaseUri "https*"
Get-ApiRequest -Method "Post"

.NOTES
#>
function Get-ApiRequest {
  [CmdletBinding()]
  param (
    [Parameter(Mandatory = $false)]
    [string]$BaseUri = $null,

    [Parameter(Mandatory = $false)]
    [string]$Method = $null
  )

  $ApiConfig = Get-ApiConfig
  
  $Requests = [System.Collections.ArrayList]@()
  foreach ($Collection in $ApiConfig.Collections.Values) {
    foreach ($Request in $Collection.Requests.Values) {
      if (!$BaseUri -or $Request.BaseUri -like $BaseUri) {
        if (!$Method -or $Request.Method -like $Method) {
          $Requests.Add($Request) | Out-Null
        }
      }
    }
  }

  return $Requests
}
Register-ArgumentCompleter -CommandName Get-ApiRequest -ParameterName BaseUri -ScriptBlock { CollectionUriArgCompleter @args }

<#
.SYNOPSIS
Show an inline CLI menu for browsing trough collections and requests

.DESCRIPTION
Show an inline CLI menu for browsing trough collections and requests

.EXAMPLE
Show-ApiRequest

.NOTES
#>
function Show-ApiRequest {
  [CmdletBinding()]

  $ApiConfig = Get-ApiConfig

  Clear-Host
  Show-ApiTrademark

  if ($null -eq $ApiConfig.Collections.Values -or $ApiConfig.Collections.Values.Count -eq 0) {
    Write-Warning "No collections and requests to display! Please make some requests first -> Invoke-ApiRequest..."
    Write-Host ""
    return
  }

  Write-ApiHeader "Requests grouped by collection (Base Uri):"
  $SortedCollections = $ApiConfig.Collections.Values | Sort-Object -Property BaseUri
  $CollectionItems = ConvertTo-CliMenuItems -Items $SortedCollections -LabelFunction { param($Col) return "$($Col.BaseUri) ($($Col.Requests.Count) Requests)" }
  $SelectedCollection = Show-CliMenu -Items $CollectionItems
  if ($null -eq $SelectedCollection) {
    Clear-Host
    return
  }

  Clear-Host

  if ($null -eq $SelectedCollection.Requests.Values -or $SelectedCollection.Requests.Values.Count -eq 0) {
    Write-Warning "No requests to display! Please make some requests first -> Invoke-ApiRequest..."
    Write-Host ""
    return
  }

  Write-ApiHeader "Requests for uri '$SelectedCollection':"
  Write-Host "Headers: $(HashtableToString -Hashtable $SelectedCollection.Headers)" -ForegroundColor DarkGray
  Write-Host ""
  $SortedRequests = $SelectedCollection.Requests.Values | Sort-Object -Property Method, Path
  $RequestItems = ConvertTo-CliMenuItems -Items $SortedRequests -LabelFunction { param($Req) return "$(ToFixedLength -Text $Req.Method -Length 8) $($Req.Path) => (Headers: $($Req.Headers.Count), Body: $($null -ne $Req.Body))" }
  $SelectedRequest = Show-CliMenu -Items $RequestItems
  if ($null -eq $SelectedRequest) {
    Clear-Host
    return
  }

  Clear-Host
  Write-ApiHeader "Actions for request '$SelectedRequest':"
  Write-Host "Method: $($SelectedRequest.Method)" -ForegroundColor DarkGray
  Write-Host "Path: $($SelectedRequest.Path)" -ForegroundColor DarkGray
  Write-Host "Headers: $(HashtableToString -Hashtable $SelectedRequest.Headers)" -ForegroundColor DarkGray
  Write-Host "Body: $($SelectedRequest.Body | ConvertTo-Json -Depth 10 -Compress)" -ForegroundColor DarkGray
  Write-Host ""
  $ActionItems = ConvertTo-CliMenuItems -Items @("Run", "Clipboard", "Details", "Remove", "Cancel")
  $Action = Show-CliMenu -Items $ActionItems
  Clear-Host

  switch ($Action) {
    "Run" {
      $SelectedRequest | Invoke-ApiRequest
    }
    "Clipboard" {
      Write-Host "Under development"
      $Body = if ($SelectedRequest.Body) { "-Body TODO" } else { "" }
      $Headers = if ($SelectedRequest.Headers) { "-Headers TODO" } else { "" }
      $PersistSessionCookie = if ($SelectedRequest.PersistSessionCookie) { "-PersistSessionCookie" }else { "" }
      $Command = "Invoke-ApiRequest -Uri '$($SelectedRequest.GetUri())' -Method $($SelectedRequest.Method) $Body $Headers $PersistSessionCookie" 
      Write-Host "Selected command is now in your clipboard" -ForegroundColor DarkGray
      Write-Host $Command -ForegroundColor DarkGray
      Set-Clipboard -Value $Command
    }
    "Details" {
      $SelectedRequest
    }
    "Remove" {
      $SelectedRequest | Remove-ApiRequest
    }
    Default {}
  }
}

<#
.SYNOPSIS
Updates the BaseUri of a collection and all its requests

.DESCRIPTION
Updates the BaseUri of a collection and all its requests

.PARAMETER BaseUri
The actual BaseUri

.PARAMETER NewBaseUri
The new BaseUri

.EXAMPLE
Update-ApiCollectionBaseUri -BaseUri "http://localhost:5020" -NewBaseUri "https://localhost:5001"

.NOTES
#>
function Update-ApiCollectionBaseUri {
  [CmdletBinding()]
  param (
    [Parameter(Mandatory = $true)]
    [string]$BaseUri,

    [Parameter(Mandatory = $true)]
    [string]$NewBaseUri
  )

  $ApiConfig = Get-ApiConfig

  $Collection = $ApiConfig.Collections[$BaseUri]
  if ($Collection) {
    # Adjust requests base uri
    foreach ($Key in $Collection.Requests.Keys) {
      $Collection.Requests[$key].BaseUri = $NewBaseUri
    }

    $NewCollection = $ApiConfig.Collections[$NewBaseUri]
    if ($NewCollection) {
      # Already exists (copy only requests)
      foreach ($Key in $Collection.Requests.Keys) {
        $NewCollection.Requests[$Key] = $Collection.Requests[$Key]
      }
      $ApiConfig.Collections.Remove($BaseUri)
    }
    else {
      # Does not exist yet
      $Collection.BaseUri = $NewBaseUri
      $ApiConfig.Collections[$NewBaseUri] = $Collection
      $ApiConfig.Collections.Remove($BaseUri)
    }

    Write-Verbose "BaseUri updated from '$BaseUri' to '$NewBaseUri'"
    Save-ApiConfig -ApiConfig $ApiConfig
  }
}
Register-ArgumentCompleter -CommandName Update-ApiCollectionBaseUri -ParameterName BaseUri -ScriptBlock { CollectionUriArgCompleter @args }

<#
.SYNOPSIS
Updates the headers of a collection

.DESCRIPTION
Updates the headers of a collection (Requests use this information to enrich their headers)

.PARAMETER BaseUri
The BaseUri/Identifier of the collection

.PARAMETER Headers
The updated headers

.EXAMPLE
Update-ApiCollectionHeader -BaseUri "https://localhost:5001" -Headers @{"X-Tenant"="traco"}

.NOTES
#>
function Update-ApiCollectionHeader {
  [CmdletBinding()]
  param (
    [Parameter(Mandatory = $true)]
    [string]$BaseUri,

    [Parameter(Mandatory = $true)]
    [hashtable]$Headers
  )

  $ApiConfig = Get-ApiConfig

  $Collection = $ApiConfig.Collections[$BaseUri]
  if ($Collection) {
    $Collection.Headers = [hashtable]@{}
    foreach ($Key in $Headers.Keys) {
      $Collection.Headers[$Key] = $Headers[$Key]
    }

    Write-Verbose "Headers updated for collection '$BaseUri'"
    Save-ApiConfig -ApiConfig $ApiConfig
  }
}
Register-ArgumentCompleter -CommandName Update-ApiCollectionHeader -ParameterName BaseUri -ScriptBlock { CollectionUriArgCompleter @args }

<#
.SYNOPSIS
Makes an http call to the given endpoint. It serializes to body to JSON and stores the request for later usage

.DESCRIPTION
This is the main function of the posht module. It wraps 'Invoke-RestMethod' and saves every request for later usage. It basically builds an inventory of requests which can be browsed and reused.
There are also functions to set common HTTP headers for collections of requests or even change the BaseUri for several requests.

.PARAMETER Method
HTTP method (Get, Post, etc.)

.PARAMETER Body
An optional body (gets serialized to JSON)

.PARAMETER PersistSessionCookie
If the request hits an auth endpoint which creates session cookies, this flag must be set, so that the cookies are reused for later requests

.PARAMETER Uri
The full Uri to the endpoint

.PARAMETER Headers
Additional request specific headers (Headers are then merged with (1) default headers from config, (2) headers from collection, (3) headers from request)

.PARAMETER SaveHeadersOnCollection
Headers specified on this request will be saved on the parent collection and reused by all future requests within this collection

.PARAMETER RequestData
Invoke-ApiRequest can also be called with 'RequestData' from a past request (see Get-ApiRequest)

.EXAMPLE
Invoke-ApiRequest -Uri "http://localhost:5020/tenants" -Method Get
Invoke-ApiRequest -Uri "http://localhost:5010/auth/credentials" -Method Post -Body @{Username="foo";Password="bar"} -PersistSessionCookie
Get-ApiRequest -BaseUri "http://localhost:5020/te*" | Invoke-ApiRequest

.NOTES
#>
function Invoke-ApiRequest {
  [CmdletBinding()]
  param (
    [Parameter(ParameterSetName = "Single")]
    [ValidateSet("Get", "Put", "Patch", "Post", "Delete")]
    [string]$Method = "Get",

    [Parameter(ParameterSetName = "Single")]
    [System.Object]$Body = $null,

    [Parameter(ParameterSetName = "Single")]
    [switch]$PersistSessionCookie = $false,

    [Parameter(Mandatory = $true, ParameterSetName = "Single")]
    [string]$Uri, # full uri

    [Parameter(ParameterSetName = "Single")]
    [hashtable]$Headers = [hashtable]@{},

    [Parameter(ParameterSetName = "Single")]
    [switch]$SaveHeadersOnCollection = $false,

    [Parameter(Mandatory = $true, ParameterSetName = "Request", ValueFromPipeline = $true)]
    [ApiRequest]$RequestData
  )

  $ApiConfig = Get-ApiConfig

  $Request = $null
  # This is a new request
  if ($null -eq $RequestData) {
    $Request = [ApiRequest]::new(
      $Headers,
      $Method,
      $Uri,
      $Body,
      $PersistSessionCookie
    )
  } 
  # Base on an existing/old request
  else {
    $Request = $RequestData
  }

  $ApiConfig.AddRequest($Request)

  # 1. Default Headers from Api Config
  $ResolvedHeaders = $ApiConfig.GetDefaultHeaders()
  # 2. Collection Headers (can overwrite)
  $Collection = $ApiConfig.Collections[$Request.BaseUri]
  if ($Collection) {
    foreach ($Key in $Collection.Headers.Keys) {
      $ResolvedHeaders[$Key] = $Collection.Headers[$Key]
    }
  }
  # 3. Request Headers (can overwrite)
  if ($Request.Headers) {
    if ($SaveHeadersOnCollection -and $Collection) {
      foreach ($Key in $Request.Headers.Keys) {
        $Collection.Headers[$Key] = $Request.Headers[$Key]
      }
    }

    foreach ($Key in $Request.Headers.Keys) {
      $ResolvedHeaders[$Key] = $Request.Headers[$Key]
    }
  }

  Save-ApiConfig -ApiConfig $ApiConfig

  Write-Verbose "$Request"
  Write-Verbose "Resolved Headers: $(HashtableToString -Hashtable $ResolvedHeaders)"

  $RestMethodArgs = [hashtable]@{
    Method               = $Request.Method
    Headers              = $ResolvedHeaders
    Uri                  = "$($Request.BaseUri)$($Request.Path)"
    SkipCertificateCheck = $true
  }

  if ($Request.Body) {
    $BodyJson = $Request.Body | ConvertTo-Json -Depth 10
    $RestMethodArgs['Body'] = $BodyJson
  }
  if ($Request.PersistSession) {
    Clear-ApiSession
    $RestMethodArgs['SessionVariable'] = "CookieSession"
  }
  $ApiSession = Get-ApiSession
  if ($null -ne $ApiSession) {
    Write-Verbose "Use existing session"
    $RestMethodArgs['WebSession'] = $ApiSession
  }

  $Response = Invoke-RestMethod @RestMethodArgs

  if ($null -ne $CookieSession) {
    Write-Verbose "Persist Session"
    Set-ApiSession $CookieSession
  }

  $Response
}
Register-ArgumentCompleter -CommandName Invoke-ApiRequest -ParameterName Uri -ScriptBlock { RequestUriArgCompleter @args }

<#
.SYNOPSIS
Removes a single api request from the saved requests

.DESCRIPTION
Removes a single api request from the saved requests

.PARAMETER Method
Post, Get, etc. -> needed to identiy the request

.PARAMETER Uri
The full uri of the request

.PARAMETER RequestData
A past request can also be used or piped

.EXAMPLE
Remove-ApiRequest -Method Get -Uri http://localhost:5020/tenants
$Request | Remove-ApiRequest

#>
function Remove-ApiRequest {
  [CmdletBinding()]
  param (
    [Parameter(ParameterSetName = "Single")]
    [ValidateSet("Get", "Put", "Patch", "Post", "Delete")]
    [string]$Method = "Get",

    [Parameter(Mandatory = $true, ParameterSetName = "Single")]
    [string]$Uri, # full uri

    [Parameter(Mandatory = $true, ParameterSetName = "Object", ValueFromPipeline = $true)]
    [ApiRequest]$Request
  )

  begin {
    $ApiConfig = Get-ApiConfig
  }

  process {
    $ResolvedRequest = $null
    if ($Request) {
      $ResolvedRequest = $Request
    }
    else {
      $ResolvedRequest = [ApiRequest]::new(
        @{},
        $Method,
        $Uri,
        $null,
        $false
      )
    }
  
    $Collection = $ApiConfig.Collections[$ResolvedRequest.BaseUri]
    if ($null -eq $Collection) {
      Write-Verbose "Did not find collection for BaseUri $($ResolvedRequest.BaseUri)"
      return
    }
  
    $RequestKey = $ResolvedRequest.GetCollectionKey()
    $RequestToDelete = $Collection.Requests[$RequestKey]
    if ($null -eq $RequestToDelete) {
      Write-Verbose "Did not find request $($ResolvedRequest.ToString())"
      return
    }
  
    $Collection.Requests.Remove($RequestKey)
    Write-Verbose "Deleted request $($ResolvedRequest.ToString())"
  }

  end {
    Save-ApiConfig -ApiConfig $ApiConfig
  }
}

<#
.SYNOPSIS
Delete an entire collection of requests

.DESCRIPTION
Delete an entire collection of requests

.PARAMETER BaseUri
The BaseUri which identifies the collection

.PARAMETER Collection
An existing collection object or trough pipe

.EXAMPLE
Remove-ApiCollection -BaseUri http://localhost:5020
Get-ApiCollection -BaseUri http://localhost:5001 | Remove-ApiCollection

#>
function Remove-ApiCollection {
  [CmdletBinding()]
  param (
    [Parameter(Mandatory = $true, ParameterSetName = "Uri")]
    [string]$BaseUri,

    [Parameter(Mandatory = $true, ParameterSetName = "Object", ValueFromPipeline = $true)]
    [ApiCollection]$Collection
  )
  
  begin {
    $ApiConfig = Get-ApiConfig
  }

  process {
    $ResolvedBaseUri = ""
    if ($BaseUri) {
      $ResolvedBaseUri = $BaseUri
    }
    else {
      $ResolvedBaseUri = $Collection.BaseUri
    }
  
    $Collection = $ApiConfig.Collections[$ResolvedBaseUri]
    if ($null -eq $Collection) {
      Write-Verbose "Did not find collection with BaseUri $ResolvedBaseUri"
      return
    }
  
    $ApiConfig.Collections.Remove($ResolvedBaseUri)
    Write-Verbose "Deleted collection with BaseUri $ResolvedBaseUri"
  }

  end {
    Save-ApiConfig -ApiConfig $ApiConfig
  }
}
Register-ArgumentCompleter -CommandName Remove-ApiCollection -ParameterName BaseUri -ScriptBlock { CollectionUriArgCompleter @args }

<#
.SYNOPSIS
Returns all session cookies if there is a session

.DESCRIPTION
Returns all session cookies if there is a session

.EXAMPLE
Get-ApiSessionCookie

#>
function Get-ApiSessionCookie {
  [CmdletBinding()]
  param ()

  $Session = Get-ApiSession
  if ($null -eq $Session) {
    Write-Verbose "No session at the moment"
    return
  }

  $Session.Cookies.GetAllCookies()
}

#endregion
