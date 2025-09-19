#region variables

$Script:ApiSession = $null
$Script:ApiConfigFileName = "posht.json"
$Script:ApiConfigFolder = ".posht"
$Script:ApiConfigFileVersion = 2
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
  [bool]$PersistSession = $false
  [bool]$SkipCertificateCheck = $false
  [bool]$Raw = $false
  [string]$BearerToken
  [int]$UsageCount = 1

  ApiRequest($ApiRequestRaw) {
    # from json
    $this.Method = $ApiRequestRaw.Method
    $this.BaseUri = $ApiRequestRaw.BaseUri
    $this.Path = $ApiRequestRaw.Path
    $this.Body = $ApiRequestRaw.Body
    $this.Headers = $ApiRequestRaw.Headers
    $this.PersistSession = $ApiRequestRaw.PersistSession
    $this.SkipCertificateCheck = $ApiRequestRaw.SkipCertificateCheck
    $this.Raw = $ApiRequestRaw.Raw
    $this.BearerToken = $ApiRequestRaw.BearerToken

    if ($ApiRequestRaw.UsageCount) { $this.UsageCount = $ApiRequestRaw.UsageCount }
    else { $this.UsageCount = 1 }
  }

  ApiRequest([hashtable]$Headers, [string]$Method, [string]$Uri, [System.Object]$Body, [bool]$PersistSession, [bool]$SkipCertificateCheck, [bool]$Raw, [string]$BearerToken) {
    # standard
    $UriObject = [Uri]::new($Uri)
    $this.Method = $Method
    $this.BaseUri = "$($UriObject.Scheme)://$($UriObject.Host):$($UriObject.Port)"
    $this.Path = "$($UriObject.LocalPath)$($UriObject.Query)"
    $this.Body = $Body
    $this.Headers = $Headers
    $this.PersistSession = $PersistSession
    $this.SkipCertificateCheck = $SkipCertificateCheck
    $this.Raw = $Raw
    $this.BearerToken = $BearerToken
  }

  [string] GetUri() {
    return "$($this.BaseUri)$($this.Path)"
  }

  [string] ToString() {
    return "$($this.Method) $($this.BaseUri)$($this.Path)"
  }

  [string] GetCollectionKey() {
    return "$($this.Method.ToLower())_$($this.Path.ToLower())"
  }

  [string] GetKey() {
    return "$($this.Method.ToLower())_$($this.BaseUri.ToLower())_$($this.Path.ToLower())"
  }
}

class ApiCollection {
  [string]$BaseUri
  [hashtable]$Headers
  [hashtable]$Requests
  [int]$UsageCount = 1

  ApiCollection($ApiCollectionRaw) {
    # from json
    $this.BaseUri = $ApiCollectionRaw.BaseUri
    $this.Headers = $ApiCollectionRaw.Headers
    $this.Requests = [hashtable]@{}

    foreach ($Request in $ApiCollectionRaw.Requests.GetEnumerator()) {
      $this.Requests[$Request.Key] = [ApiRequest]::new($Request.Value)
    }

    if ($ApiCollectionRaw.UsageCount) { $this.UsageCount = $ApiCollectionRaw.UsageCount }
    else { $this.UsageCount = $this.Requests.Count }
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
    return $this.BaseUri.ToLower()
  }
}

class ApiConfig {
  [string] $Id
  [int] $Version
  [hashtable] $DefaultHeaders
  [hashtable] $Collections
  [datetime] $LastUpdate

  ApiConfig() {
    # empty/new config
    $this.Id = (New-Guid).Guid
    $this.Version = $Script:ApiConfigFileVersion
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
    if (-Not $this.Id) {
      $this.Id = (New-Guid).Guid
    }

    $this.Version = $ApiConfigRaw.Version
    if (-Not $this.Version) {
      $this.Version = 0 # Must be an old config file -> apply migrations
    }

    $this.DefaultHeaders = $ApiConfigRaw.DefaultHeaders
    $this.LastUpdate = $ApiConfigRaw.LastUpdate
    $this.Collections = [hashtable]@{}
    foreach ($Collection in $ApiConfigRaw.Collections.GetEnumerator()) {
      $this.Collections[$Collection.Key] = [ApiCollection]::new($Collection.Value)
    }
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
      $ReqColKey = $Request.GetCollectionKey()
      $ExistingCollection.UsageCount++
      $ExistingRequest = $ExistingCollection.Requests[$ReqColKey]
      if ($ExistingRequest) { $Request.UsageCount = $ExistingRequest.UsageCount + 1 }
      
      # Add/Overwrite
      $ExistingCollection.Requests[$ReqColKey] = $Request
    }
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

# Source external functions
. $PSScriptRoot\Functions\ConvertTo-Expression.ps1

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

    $RawApiConfig = $ConfigFile | ConvertFrom-Json -Depth 10 -AsHashtable
    $ApiConfig = [ApiConfig]::new($RawApiConfig)
    Start-Migrations -ApiConfig $ApiConfig

    return $ApiConfig
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

function Write-ClearedLine {
  param(
    [string]$Text,
    [int]$ClearingWidth,
    [ConsoleColor]$ForegroundColor = $Host.UI.RawUI.ForegroundColor
  )
  # pad text to width, truncate if longer
  $Line = $Text.PadRight($ClearingWidth).Substring(0, $ClearingWidth)
  Write-Host $Line -ForegroundColor $ForegroundColor
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
  [CmdletBinding()]
  param (
    [Parameter(Mandatory = $true)]
    [CliMenuItem[]]$Items,

    [Parameter()]
    [switch]$ReturnIndex = $false,

    [Parameter()]
    [bool]$Multiselect = $false
  )

  $VKeyCode = 0
  $Position = 0
  $Selection = @()

  if ($Items.Count -gt 0) {
    try {
      [System.Console]::CursorVisible = $false #prevents cursor flickering

      $StartPos = [System.Console]::CursorTop
      $PageSize = ([System.Console]::WindowHeight - $StartPos) - 5
      $WindowStart = 0
      $WindowEnd = [Math]::Min($PageSize - 1, $Items.Count - 1) # -1 because window end is used as an inclusive index

      Build-CliMenu -Items $Items[$WindowStart..$WindowEnd] -RelativePosition $Position -Multiselect $Multiselect -Selection $Selection -Offset $WindowStart -TotalCount $Items.Count
      
      While (
        $VKeyCode -ne 13 -and $VKeyCode -ne 27) {
        $Options = [System.Management.Automation.Host.ReadKeyOptions]"IncludeKeyDown", "NoEcho";
        $PressedKey = $Host.UI.RawUI.ReadKey($Options)
        $VKeyCode = $PressedKey.VirtualKeyCode
        # 38=up-arrow,40=down-arrow,36=home,35=end,27=esc,13=enter
        if ($VKeyCode -eq 38 -or $PressedKey.Character -eq 'k') { $Position-- } #go up
        elseif ($VKeyCode -eq 40 -or $PressedKey.Character -eq 'j') { $Position++ } #go down
        elseif ($VKeyCode -eq 36) { $Position = 0 } #top
        elseif ($VKeyCode -eq 35) { $Position = $Items.Count - 1 } #bottom
        elseif ($PressedKey.Character -eq ' ') { $Selection = Set-CliMenuSelection $Position $Selection }
        
        if ($Position -lt 0) { $Position = 0 }
        if ($VKeyCode -eq 27) { $Position = $null }
        if ($Position -ge $Items.Count) { $Position = $Items.Count - 1 }

        # Adjust window end and start values
        if ($Position -lt $WindowStart) {
          $WindowStart = $Position
          $WindowEnd = [Math]::Min($WindowStart + $PageSize - 1, $Items.Count - 1)
        }
        elseif ($Position -gt $WindowEnd) {
          $WindowEnd = $Position
          $WindowStart = [Math]::Max(0, $WindowEnd - $PageSize + 1)
        }

        # NO ESCAPE (Setting the Cursor)
        if ($VKeyCode -ne 27) {
          # $StartPos = ([System.Console]::CursorTop - ($WindowEnd - $WindowStart)) - 2
          [System.Console]::SetCursorPosition(0, $StartPos)

          $RelativePos = $Position - $WindowStart
          Build-CliMenu -Items $Items[$WindowStart..$WindowEnd] -RelativePosition $RelativePos -Multiselect $Multiselect -Selection $Selection -Offset $WindowStart -TotalCount $Items.Count
        }
      }
    }
    finally {
      [System.Console]::SetCursorPosition(0, $StartPos + ($WindowEnd - $WindowStart + 2))
      [System.Console]::CursorVisible = $true
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

function Build-CliMenu {
  param (
    [Parameter(Mandatory = $true)]
    [CliMenuItem[]]$Items,

    [Parameter(Mandatory = $true)]
    [int]$RelativePosition,

    [Parameter(Mandatory = $false)]
    [bool]$Multiselect = $false,

    [Parameter()]
    [array]$Selection = @(),

    [Parameter()]
    [int]$Offset = 0,

    [Parameter(Mandatory = $true)]
    [int]$TotalCount
  )

  $ConsoleWidth = [System.Console]::WindowWidth

  if ($Offset -gt 0) {
    Write-ClearedLine -Text "   ... more above ..." -ForegroundColor DarkGray -ClearingWidth $ConsoleWidth
  }
  else {
    Write-ClearedLine -Text "" -ClearingWidth $ConsoleWidth # empty line if no indicator, keeps alignment
  }

  for ($i = 0; $i -lt $Items.Count; $i++) {
    $AbsoluteIndex = $i + $Offset
    
    if ($null -ne $Items[$i]) {
      $Label = $Items[$i].Label

      if ($Multiselect) {
        if ($Selection -contains $AbsoluteIndex) {
          $Label = '[x] ' + $Label
        }
        else { 
          $Label = '[ ] ' + $Label
        }
      }

      if ($i -eq $RelativePosition) {
        Write-ClearedLine ">> $Label" -ForegroundColor Green -ClearingWidth $ConsoleWidth
      }
      else {
        Write-ClearedLine "   $Label" -ClearingWidth $ConsoleWidth
      }
    }
  }

  # --- show "more below" indicator ---
  if ($Offset + $Items.Count -lt $TotalCount) {
    Write-ClearedLine "   ... more below ..." -ForegroundColor DarkGray -ClearingWidth $ConsoleWidth
  }
  else {
    Write-ClearedLine "" -ClearingWidth $ConsoleWidth # empty line if no indicator, keeps alignment
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

function Show-CollectionsMenu {
  param (
    [Parameter(Mandatory)]
    [ApiConfig]
    $ApiConfig,

    [Parameter(Mandatory = $false)]
    [bool]$OrderByUsage = $false
  )
  
  Show-ApiTrademark
  
  Write-Host "NOTE: Use Arrow Keys to navigate, Enter to approve/select and Esc to navigate back" -ForegroundColor DarkGray
  Write-Host ""

  if ($null -eq $ApiConfig.Collections.Values -or $ApiConfig.Collections.Values.Count -eq 0) {
    Write-Warning "No collections and requests to display! Please make some requests first -> Invoke-ApiRequest..."
    Write-Host ""
    return
  }

  Write-ApiHeader "Requests grouped by Collection (Base Uri)"
  if ($OrderByUsage) { $SortedCollections = $ApiConfig.Collections.Values | Sort-Object -Property @{Expression = "UsageCount"; Descending = $true }, @{Expression = "BaseUri"; Descending = $false } }
  else { $SortedCollections = $ApiConfig.Collections.Values | Sort-Object -Property BaseUri }
  
  $CollectionItems = ConvertTo-CliMenuItems -Items $SortedCollections -LabelFunction { param($Col) return "$($Col.BaseUri.ToLower()) ($($Col.Requests.Count) Requests)" }
  $SelectedCollection = Show-CliMenu -Items $CollectionItems
  Clear-Host

  if ($SelectedCollection) {
    Show-RequestsMenu -ApiConfig $ApiConfig -Collection $SelectedCollection -OrderByUsage $OrderByUsage
  }
}

function Show-RequestsMenu {
  param (
    [Parameter(Mandatory)]
    [ApiConfig]
    $ApiConfig,

    [Parameter(Mandatory)]
    [ApiCollection]
    $Collection,

    [Parameter(Mandatory = $false)]
    [bool]$OrderByUsage = $false
  )

  if ($null -eq $Collection.Requests.Values -or $Collection.Requests.Values.Count -eq 0) {
    Write-Warning "No requests to display! Please make some requests first -> Invoke-ApiRequest..."
    Write-Host ""
    
    Show-CollectionsMenu -ApiConfig $ApiConfig
  }

  Write-ApiHeader "Requests for Base Uri '$Collection'"
  Write-Host "Headers: $($Collection.Headers | ConvertTo-Json -Depth 2 -Compress)" -ForegroundColor DarkGray
  Write-Host "Requests: $($Collection.Requests.Count)" -ForegroundColor DarkGray
  Write-Host ""

  if ($OrderByUsage) { $SortedRequests = $Collection.Requests.Values | Sort-Object -Property @{Expression = "UsageCount"; Descending = $true }, @{Expression = "Path"; Descending = $false } }
  else { $SortedRequests = $Collection.Requests.Values | Sort-Object -Property Path, Method }

  $RequestItems = ConvertTo-CliMenuItems -Items $SortedRequests -LabelFunction { param($Req) return "$(ToFixedLength -Text $Req.Method.ToUpper() -Length 8) $($Req.Path) => (Usage: $($Req.UsageCount), Headers: $($Req.Headers.Count), Body: $($null -ne $Req.Body))" }
  $SelectedRequest = Show-CliMenu -Items $RequestItems -ErrorAction Stop
  Clear-Host

  if ($SelectedRequest) {
    Show-RequestDetailMenu -ApiConfig $ApiConfig -Collection $Collection -Request $SelectedRequest
  }
  else {
    Show-CollectionsMenu -ApiConfig $ApiConfig -OrderByUsage $OrderByUsage
  }
}

function Show-RequestDetailMenu {
  param (
    [Parameter(Mandatory)]
    [ApiConfig]
    $ApiConfig,

    [Parameter(Mandatory)]
    [ApiCollection]
    $Collection,

    [Parameter(Mandatory)]
    [ApiRequest]
    $Request
  )

  Write-ApiHeader "Actions for request '$Request'"
  Write-Host "Method: $($Request.Method.ToUpper())" -ForegroundColor DarkGray
  Write-Host "Path: $($Request.Path)" -ForegroundColor DarkGray
  Write-Host "Headers: $($Request.Headers | ConvertTo-Json -Depth 2 -Compress)" -ForegroundColor DarkGray
  Write-Host "Body: $($Request.Body | ConvertTo-Json -Depth 10 -Compress)" -ForegroundColor DarkGray
  Write-Host "Usage count: $($Request.UsageCount)" -ForegroundColor DarkGray
  Write-Host ""
  $ActionItems = ConvertTo-CliMenuItems -Items @("Run", "Clipboard", "Details", "Remove", "Cancel")
  $Action = Show-CliMenu -Items $ActionItems
  Clear-Host

  switch ($Action) {
    "Run" {
      $Request | Invoke-ApiRequest
    }
    "Clipboard" {
      $Body = if ($Request.Body) { "-Body $(ConvertTo-Expression -Object $Request.Body -Expand -1)" } else { "" }
      $Headers = if ($Request.Headers) { "-Headers $(ConvertTo-Expression -Object $Request.Headers -Expand -1)" } else { "" }
      $PersistSessionCookie = if ($Request.PersistSessionCookie) { "-PersistSessionCookie" }else { "" }
      $Command = "Invoke-ApiRequest -Uri '$($Request.GetUri())' -Method $($Request.Method) $Body $Headers $PersistSessionCookie" 
      Write-Host "Selected command is now in your clipboard" -ForegroundColor DarkGray
      Write-Host $Command -ForegroundColor DarkGray
      Set-Clipboard -Value $Command
    }
    "Details" {
      $Request
    }
    "Remove" {
      $Request | Remove-ApiRequest
    }
    Default {
      Show-RequestsMenu -ApiConfig $ApiConfig -Collection $Collection -OrderByUsage $OrderByUsage
    }
  }
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
  if ($Local) {
    $FullPath = Get-ApiConfigFilePath -Source Local
  }
  else {
    $FullPath = Get-ApiConfigFilePath -Source UserProfile 
  }

  $FileExists = Test-Path $FullPath
  if (-Not $FileExists -or $PSCmdlet.ShouldProcess("This will create a new config file under '$FullPath' and overwrite the existing one!", $FullPath, 'Initialize new config file and overwrite the existing one?')) {
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
    [Parameter(Position = 0)]
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
    [Parameter(Mandatory = $false, Position = 0)]
    [string]$BaseUri = $null,

    [Parameter(Mandatory = $false, Position = 1)]
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
  param (
    [Parameter(Mandatory = $false, Position = 0)]
    [switch]$OrderByUsage
  )

  $ApiConfig = Get-ApiConfig

  Clear-Host
  
  Show-CollectionsMenu -ApiConfig $ApiConfig -OrderByUsage $OrderByUsage
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
    [Parameter(Mandatory = $true, Position = 0, ValueFromPipeline = $true)]
    [string]$BaseUri,

    [Parameter(Mandatory = $true, Position = 1)]
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
    [Parameter(Mandatory = $true, Position = 0, ValueFromPipeline = $true)]
    [string]$BaseUri,

    [Parameter(Mandatory = $true, Position = 1)]
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

.PARAMETER Raw
Output raw response

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

    [Parameter(Mandatory = $true, Position = 0, ParameterSetName = "Single")]
    [string]$Uri, # full uri

    [Parameter(ParameterSetName = "Single")]
    [hashtable]$Headers = [hashtable]@{},

    [Parameter(ParameterSetName = "Single")]
    [switch]$SaveHeadersOnCollection = $false,
    
    [Parameter(ParameterSetName = "Single")]
    [switch]$SkipCertificateCheck = $false,
    
    [Parameter(ParameterSetName = "Single")]
    [switch]$NoHistory = $false,
    
    [Parameter(ParameterSetName = "Single")]
    [switch]$Raw = $false,
    
    [Parameter(ParameterSetName = "Single")]
    [string]$BearerToken,

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
      $PersistSessionCookie,
      $SkipCertificateCheck,
      $Raw,
      $BearerToken
    )
  } 
  # Base on an existing/old request
  else {
    $Request = $RequestData
  }

  if (-Not $NoHistory) {
    $ApiConfig.AddRequest($Request)
  }

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

  if ($Request.BearerToken) {
    $ResolvedHeaders["Authorization"] = "Bearer $($Request.BearerToken)"
  }

  if (-Not $NoHistory) {
    Save-ApiConfig -ApiConfig $ApiConfig
  }

  Write-Verbose "$Request"
  Write-Verbose "Resolved Headers: $($ResolvedHeaders | ConvertTo-Json -Depth 2 -Compress)"

  $WebRequestArgs = [hashtable]@{
    Method               = $Request.Method
    Headers              = $ResolvedHeaders
    Uri                  = "$($Request.BaseUri)$($Request.Path)"
    SkipCertificateCheck = $Request.SkipCertificateCheck
    ErrorAction          = 'Stop'
  }

  if ($Request.Body) {
    $BodyJson = $Request.Body | ConvertTo-Json -Depth 10
    $WebRequestArgs['Body'] = $BodyJson
  }
  if ($Request.PersistSession) {
    Clear-ApiSession
    $WebRequestArgs['SessionVariable'] = "SessionVarTemp"
  }
  $ApiSession = Get-ApiSession
  if ($null -ne $ApiSession -and -not $Request.BearerToken) {
    Write-Verbose "Use existing session"
    $WebRequestArgs['WebSession'] = $ApiSession
  }

  try {
    $Response = Invoke-WebRequest @WebRequestArgs
    Write-Verbose "Status code: $($Response.StatusCode) $($Response.StatusDescription)"
    if ($Response -and -not $Request.Raw) {
      $Response = $Response.Content | ConvertFrom-Json -Depth 20
    }

    if ($null -ne $SessionVarTemp -and $Request.PersistSession) {
      Write-Verbose "Persist Session"
      $null = $SessionVarTemp.Headers.Remove("Authorization")
      #TODO: When to remove cookies and when to remove bearer token
      #$ApiSession.Cookies = [System.Net.CookieContainer]::new(4)
      Set-ApiSession $SessionVarTemp
    }
  
    return $Response
  }
  catch {
    Write-Verbose "Status code: $($_.Exception.StatusCode)"
    throw $_
  }
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
    [Parameter(ParameterSetName = "Single", Position = 1)]
    [ValidateSet("Get", "Put", "Patch", "Post", "Delete")]
    [string]$Method = "Get",

    [Parameter(Mandatory = $true, Position = 0, ParameterSetName = "Single")]
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
    [Parameter(Mandatory = $true, Position = 0, ParameterSetName = "Uri")]
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

#region schema migrations

function Start-Migrations {
  param (
    [Parameter(Mandatory = $true)]
    [ApiConfig]$ApiConfig
  )

  if ($ApiConfig.Version -eq $Script:ApiConfigFileVersion) { return }

  #V1: Lowercase hashtable keys  
  if ($ApiConfig.Version -lt 1) {
    Write-Verbose "Run Migration 1: Lowercase hashtable keys"
    $Collections = [hashtable]@{}
    foreach ($Collection in $ApiConfig.Collections.Values) {
      $Requests = [hashtable]@{}
      foreach ($Request in $Collection.Requests.Values) {
        # Fix Path
        $PathAndQuery = $Request.Path.Split('?')
        $Request.Path = "$($PathAndQuery[0].ToLower())"
        if ($null -ne $PathAndQuery[1]) { $Request.Path += "?$($PathAndQuery[1])" }

        $Requests[$Request.GetCollectionKey()] = $Request
      }
      $Collection.Requests = $Requests
      $Collections[$Collection.GetKey()] = $Collection
    }
    $ApiConfig.Collections = $Collections
    $ApiConfig.Version = 1
    Save-ApiConfig -ApiConfig $ApiConfig
  }

  if($ApiConfig.Version -lt 2){
    # Make a backup but no structural changes
    $ConfigFilePath = Resolve-ApiConfigFilePath
    $BackupPath = $ConfigFilePath.Replace($Script:ApiConfigFileName, "posht_$(Get-Date -Format "MM-dd-yyyyTHH-mm").json")
    Save-ApiConfig -ApiConfig $ApiConfig -FullPath $BackupPath

    $ApiConfig.Version = 2
    Save-ApiConfig -ApiConfig $ApiConfig
  }
}

#endregion

#region alias

New-Alias iar -Value Invoke-ApiRequest -ea silentlycontinue
New-Alias sar -Value Show-ApiRequest -ea silentlycontinue

#endregion
