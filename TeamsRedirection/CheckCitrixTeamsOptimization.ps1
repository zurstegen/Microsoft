<#
.SYNOPSIS
  Check Citrix Teams Optimization

.DESCRIPTION
  Powershell Script to run as ControlUp Action to check, if the Citrix Teams Optimization is running

.SOURCES
  https://techcommunity.microsoft.com/t5/microsoft-teams/still-connecting-to-remote-devices/m-p/1906370
  https://docs.citrix.com/en-us/citrix-virtual-apps-desktops/multimedia/opt-ms-teams.html
  https://docs.citrix.com/en-us/citrix-virtual-apps-desktops/multimedia/opt-ms-teams.html#known-limitations
  https://docs.microsoft.com/en-us/MicrosoftTeams/msi-deployment#clean-up-and-redeployment-procedure
  https://docs.microsoft.com/en-us/MicrosoftTeams/teams-for-vdi
  
  The idea and some sources are from Marcel Calef (https://www.controlup.com/script-library-posts/check-citrix-teams-optimization-readiness/) and Dennis Mohrmann (https://github.com/Mohrpheus78/Citrix/blob/main/Teams%20Optimization%20check/Check%20Teams%20optimization.ps1).

.PARAMETER
   [string]$SessionID,
   [version]$vdaVer,
   [string]$protocol,
   [version]$ctxRx,
   [string]$userChanges 

.INPUTS
   SessionID,
   VDAVersion
   Protocol
   Citrix Receiver Version
   User  Changes

.OUTPUTS
   Citrix Teams Optimization Information
  
.EXAMPLE
   

.NOTES
  Script-Name  : ControlUp_CheckCitrixTeamsOptimization.ps1
  Version      : 1.0
  Date         : 28.01.2021
  Author       : Toias Zurstegen
  E-Mail       : 
  Company      : 

.HISTORY
  | Date      | Name                   | Description
  ---------------------------------------------------------------------------------------------------------------------------------
   12.01.2021   Tobias Zurstegen         Initial Draft

#>

[CmdLetBinding()]
Param (
    [Parameter(Mandatory=$true,HelpMessage='SessionID')]             [string]$SessionID,
    [Parameter(Mandatory=$false, HelpMessage='Citrix VDA ver.')]     [version]$vdaVer,
    [Parameter(Mandatory=$false, HelpMessage='protocol')]            [string]$protocol,
    [Parameter(Mandatory=$false, HelpMessage='Citrix Client ver.')]  [version]$ctxRx,
    [Parameter(Mandatory=$false, HelpMessage='userChanges')]         [string]$userChanges
)

<#

[string]$SessionID = "6"
[version]$vdaVer = "1912.0.3000.3293"
[string]$protocol = "HDX"
[version]$ctxRx = "19.12.6000.9"
[string]$userChanges = "Discard"
#>
Set-StrictMode -Version Latest
[string]$ErrorActionPreference = 'Stop'
$VerbosePreference = 'Continue'      # Remove the comment in the begining to enable Verbose outut

Write-Verbose "====================== Verbose Input ========================"
Write-Verbose "   SessionID :  $SessionID"  ## Not showing to allow better results grouping
Write-Verbose "      vdaVer :  $vdaVer"
Write-Verbose "    protocol :  $protocol"
Write-Verbose "       ctxRx :  $ctxRx"

#########################################################################
#####                         Variables                              ####
#########################################################################

# Check if the VDA supports it (1906 or newer)
[version]$WindowsVDAMin = "1903.0.0.0"
[version]$WindowsClientMin = "19.7.0.15"
[version]$MacClientMin = "20.12.0.3"
[version]$LinuxClientMin = "20.06.0.15"
[boolean]$StatusCtxRx = $false
[boolean]$StatusVDA = $false
[boolean]$StatusCtxTeamsSvc = $false
[boolean]$StatusTeamsRedirPol = $false
[boolean]$StatususerMSTeamsSup = $false
[boolean]$StatusMachineInstall = $false
[boolean]$StatusTeamsRunning = $false
[boolean]$StatusHdxRedir = $false
[boolean]$StatusVCWebRtc = $false

#########################################################################
#### Citrix components versions and capability validations           ####
#########################################################################

# If not a Citrix session - no need to continue
if($protocol -ne "HDX" -and $protocol -ne "Console"){Write-Output "INFO :   Not a Citrix session. Exiting"; exit }

# VDA Version - Check
if($vdaVer -gt $WindowsVDAMin) {
    $vdaVerTest = $true
}
else {
    $vdaVer = $false
}
$StatusVDA = $vdaVerTest

# Citrix Receiver Version - Check
$ClientProductId=(Get-ItemProperty HKLM:\Software\Citrix\ICA\Session\$SessionID\Connection -name ClientProductId).ClientproductId
if ($ClientProductId -eq 1) {$ClientPlatform="Windows"}
if ($ClientProductId -eq 81) {$ClientPlatform="Linux"}
if ($ClientProductId -eq 82) {$ClientPlatform="Mac"}
if ($ClientProductId -eq 257) {$ClientPlatform="HTML5"}

# Citrix Client Platform
switch ($ClientPlatform)
{
	'Windows'	{
				    if ($ctxRx -gt $WindowsClientMin) { $ctxRxVerTest = $true }
                    else { $ctxRxVerTest = $false }
				}
				
	'Mac'		{
				    if ($ctxRx -gt $MacClientMin) { $ctxRxVerTest = $true }
				    else { $ctxRxVerTest = $false }
				}
				
	'Linux'		{
				    if ($ctxRx -lt $LinuxClientMin) { $ctxRxVerTest = $true }
				    else { $ctxRxVerTest = $false }
				}
    'HTML5'     {
                    $ctxRxVerTest = $false
                }
}
$StatusCtxRx = $ctxRxVerTest


# Check if the VDA has the webSockets service running
Try{$CtxTeamsSvc = ((Get-Service CtxTeamsSvc).status -match "Running")}
catch {$CtxTeamsSvc = $false} # return $false if service not running
$StatusCtxTeamsSvc = $CtxTeamsSvc

 # Check the WebBrowserRedirection Policy  1=enabled (implicitly enabled if not found in VDA > 7.??)
$redirPol = (get-itemproperty -path HKLM:\SOFTWARE\Policies\Citrix\$SessionID\User\MultimediaPolicies  -name "TeamsRedirection" -ErrorAction Ignore)
if ($redirPol -ne $null) {
    $redirPol = $redirPol.TeamsRedirection
}
if($redirPol -eq $null -and $vdaVerTest -eq $true) {
    $redirPol = 2
}

if($redirPol -eq 1 -or $redirPol -eq 2){
    $StatusTeamsRedirPol = $true
}

# check HKEY_CURRENT_USER\SOFTWARE\Citrix\HDXMediaStream\\MSTeamsRedirSupport
## Teams will look for this to decide to enable or not redirection
Try {$userMSTeamsSupp = (Get-ItemProperty -Path hkcu:software\Citrix\HDXMediaStream -Name "MSTeamsRedirSupport").MSTeamsRedirSupport}
Catch {$userMSTeamsSupp = "notFound" }

if($userMSTeamsSupp -eq 1){
    $StatusTeamsRedirPol = $true
}

# Check if the CVAD Persist User Changes was provided, if not set as unknown
if (!($userChanges -match '.+')) {$userChanges = 'Not Provided'}
Write-Verbose " userChanges :  $userChanges"

###############################################################################################################
# Teams install mode, version and session log entries

# Check Teams executable path
Try { $machineInstall = ((Test-Path "${env:ProgramFiles(x86)}\Microsoft\Teams\current\Teams.exe") -or (Test-Path "$env:ProgramFiles\Microsoft\Teams\current\Teams.exe")) }
Catch {$machineInstall = "False"}
$StatusMachineInstall = $machineInstall

Try { $userInstall = (test-path "$env:LOCALAPPDATA\Microsoft\Teams\") }
Catch {$userInstall = "False"}

# Check if MSI install is allowed

#old 
#Try{$preventMSIinstall = (Get-Itemproperty HKCU:Software\Microsoft\Office\Teams).PreventInstallationFromMsi}
#     Catch{$preventMSIinstall = 'not found'}

###############################################################################################################
# Find the teams.exe root process and get it's PID
 Try {
        $teams = (Get-Process teams | Where-Object {$_.mainWindowTitle}) # get the teams process with the visible window.
        $teamsPID = $teams.id
 }
         #$teamsVer = $teams.FileVersion}
 Catch {$teamsPID = 'n/a'} #; $teamsVer = 'not running' }

# Check if Teams.exe received the Citrix HDX Redirection RegKey (would be 1, else 0 or not found)
if ($teamsPID -gt 0 -and $teamsPID -ne "n/a"){
    Try {
        $hdxRedirLogEntry = ((Select-String -path "$env:appdata\Microsoft\Teams\logs.txt" -Pattern "<$teamsPID> -- info -- vdiUtility: citrixMsTeamsRedir")[-1]).ToString()
        $hdxRedir = $hdxRedirLogEntry.Substring($hdxRedirLogEntry.Length -2, 2)
    }
    Catch {$hdxRedir = "notFound"}
    $StatusTeamsRunning = $true
}
else {$hdxRedir = "not running"}

if($hdxRedir -match 1) { $StatusHdxRedir = $true}

# Check Virutal Channel WebRTC
$VCWebRTC = (Get-WmiObject -Namespace root\citrix\hdx -Class Citrix_VirtualChannel_Webrtc_Enum | Where-Object {$_.SessionID -eq $SessionID})
if($VCWebRTC -ne $null -or $VCWebRTC.IsActive -ne "Inactive")
{
    $VCWebRTCActualPriority = $VCWebRTC.Component_ActualPriority
    $VCWebRTCCallState = $VCWebRTC.Component_CallState
    $VCWebRTCIsActive = $VCWebRTC.IsActive
    $VCWebRTCIsEnabled = $VCWebRTC.IsEnabled
    $VCWebRTCAudioInput = $VCWebRTC.Component_Device_audio
    $VCWebRTCSpeaker = $VCWebRTC.Component_Device_speaker
    $VCWebRTCWebCam = $VCWebRTC.Component_Device_video
}
if(($VCWebRTC.Component_VersionTypescript -ne "" -and $VCWebRTC.IsActive -eq "Active") -or ($VCWebRTC.IsActive -eq "Active" -and $VCWebRTC.Component_VersionTypescript -eq "0.0.0.0" ))
{
    $VCWebRTCStatus = $true
}
else { $VCWebRTCStatus = $false }
$StatusVCWebRtc = $VCWebRTCStatus
    
#####################################################
#####                OUTPUT                     #####
#####################################################

# General Information
Write-Output "`n========================== General ==========================="
Write-Output "VDA Version:                         $vdaVer"
Write-Output "User Changes:                        $userChanges"
Write-Output "Client Plattform:                    $ClientPlatform"
Write-Output "Citrix Workspace App Version:        $ctxRx"
    Write-Output "Virtual Channel Enabled:             $VCWebRTCIsEnabled"
    Write-Output "Virtual Channel Active:              $VCWebRTCIsActive"
if($VCWebRTC.IsActive -ne "Inactive"){
    Write-Output "Virtual Channel Web RTC Priority:    $VCWebRTCActualPriority"

    if($VCWebRTC.Component_CallState -ne "unknown") {
        Write-Output "Virtual Channel Call State:          $VCWebRTCCallState"
    }
    if($VCWebRTC.Component_Device_audio -ne "") {
        Write-Output "Virtual Channel Speaker:             $VCWebRTCSpeaker"
    }
    if($VCWebRTC.Component_Device_speaker -ne "") {
        Write-Output "Virtual Channel Microphone:          $VCWebRTCAudioInput"
    }
    if($VCWebRTC.Component_Device_video -ne "") {
        Write-Output "Virtual Channel WebCam:              $VCWebRTCWebCam"
    }
}

# Citrix Readiness
Write-Output "`n====================== Citrix Readiness ======================"

# VDA
if ($vdaVerTest) {
    Write-Output "PASS:       VDA Version $vdaVer supports HDX Teams Optimization" 
}
else {
    Write-Output "`n======!!======!!"
    Write-Output "FAIL:       VDA Version $vdaVer does not support HDX Teams Optimization (or not found in the output)"
    Write-Output "      TRY:  Upgrade VDA to 1903 or newer. see https://docs.citrix.com/en-us/tech-zone/learn/poc-guides/microsoft-teams-optimizations.html"
}
     
# Citrix Receiver       
if ($ctxRxVerTest) {
    Write-Output "PASS:       Citrix Workspace App Version $ctxRx supports HDX Teams Optimization"
}
else {
    Write-Output "`n======!!======!!"
    Write-Output "FAIL:       Receiver/CWA Version $ctxRx is old and does not support HDX Teams Optimization "
    Write-Output "      TRY:  Upgrade the Client device to latest version of Citrix Workspace App"
    if ($vdaVerTest -eq $false) {exit}
}

#HDX Policy
if ($redirPol -eq 0)  {
    Write-Output "`n======!!======!!"
    Write-Output "FAIL:       HDX Teams Optimization DISABLED explicitly via policy and the VDA is to old!"
    Write-Output "      TRY:  Review Citrix Policies in Citrix Studio"
    exit
}

if ($redirPol -eq 1)  {
    Write-Output "PASS:       HDX Teams Optimization policy explicitly ENABLED from Citrix Studio"
}

if ($redirPol -eq 2)  {
    Write-Output "PASS:       HDX Teams Optimization policy is ENABLED as Default"
}
  
if ($CtxTeamsSvc) {
    Write-Output "PASS:       HDX Teams Optimization (CtxTeamsSvc) found running in the VDA" 
}
else { 
    Write-Output "`n======!!======!!"
    if ($redirPol -eq "notFound") {
        Write-Output "      INFO: DX Teams Optimization policy not set explicitly via policy"
        Write-Output "      TRY:  Review Citrix Policies in Citrix Studio & Enable HDX Browser content redirection"
        Write-Output "            Check if the HDX Teams Optimization service is running on the VDA"
     }
     Write-Output "FAIL:       HDX Teams Optimization service (CtxTeamsSvc) not running "
     Write-Output "TRY:        Check if the CtxTeamsSvc service is running on the VDA"
}

# HKEY_CURRENT_USER\SOFTWARE\Citrix\HDXMediaStream   MSTeamsRedirSupport  will be 1 if VDA and CWA support it.
Switch ($userMSTeamsSupp)
{
    '1'              {
                        Write-Output "PASS:       Citrix reports this HDX session supports Teams Optimization (MSTeamsRedirSupport is 1)"
                        if (!$CtxTeamsSvc) {Write-Output "      INFO:  See warning for CtxTeamsSvc"}
                     }
    '0'              { 
                        Write-Output "WARN:       Citrix HDX redirection for Teams not supported on this session (MSTeamsRedirSupport is not 1)" 
                        Write-Output "      TRY:  Review Citrix VDA and Workspace App versions or DIsconnect and reconnect the session"
                     }
    'notFound'       { 
                        Write-Output "WARN:       Citrix HDX redirection for Teams not supported on this session (MSTeamsRedirSupport not found in HKCU)"
                     }
}

Write-Output "`n====================== Teams Readiness ======================"

# Teams Machine Installation
if ($machineInstall) {
    Write-Output "PASS:       Teams found in the Program Files directory"
}
else {
    Write-Output "`n======!!======!!"
    Write-Output "WARN :      Teams not found in the Program Files directory. "
    if ((test-path "$env:LOCALAPPDATA\Microsoft\Teams\") -and !($userChanges -match 'Local')) { 
        Write-Output "WARN :      Teams found in the User's Local AppData folder and VDA is not persistent."
        Write-Output "SEE:        https://docs.microsoft.com/en-us/MicrosoftTeams/teams-for-vdi#non-persistent-setup"
    }
    if ($preventMSIinstall -match '1') { 
        Write-Output "WARN :      PreventInstallationFromMSI variable found at HKCU:Software\Microsoft\Office\Teams"
        Write-Output "SEE         https://docs.microsoft.com/en-us/MicrosoftTeams/msi-deployment#clean-up-and-redeployment-procedure"
    }
}

# WebRTC Virtual Channel Citrix Teams Redirection
    
# Teams HDX Redirection AppData Logging                       
Switch -Wildcard ($hdxRedir)
{     '*1*'             { 
                            Write-Output "PASS:       Teams reports Citrix HDX Optimized - in the GUI: User-> About->Version"
                        }
      '*0*'             { 
                            Write-Output "`n======!!======!!"
                            Write-Output "WARN:       Citrix HDX NOT Optimized - in the GUI: User-> About->Version"
                        }
      'not running'     {
                            Write-Output "`n======!!======!!"
                            Write-Output "INFO:       Teams was not detected running in this session"
                        }
      default           { 
                            Write-Output "`n======!!======!!"
                            Write-Output "WARN:       Teams did not detect Citrix HDX optimization"
                        }
}

Write-Output "`n*************************************************************"

Write-Output "`n========================= Result ============================"
if($StatusCtxRx -eq $true -and $StatusVDA -eq $true -and $StatusCtxTeamsSvc -eq $true -and $StatusTeamsRedirPol -eq $true -and $StatusMachineInstall -eq $true -and $StatusTeamsRunning -eq $true -and $StatusHdxRedir -eq $true -and $StatusVCWebRtc -eq $true) {
    Write-Output "PASS:       Citrix Teams Optimization Check pass and success"
}
else{ 
    Write-Output "WARN:        Citrix Teams Optimization Check failed 'n" 
    Write-Output "WARN:        Status Citrix Receiver:            $StatusCtxRx"
    Write-Output "WARN:        Status VDA:                        $StatusVDA"
    Write-Output "WARN:        Status Citrix Teams Service:       $StatusCtxTeamsSvc"
    Write-Output "WARN:        Status Teams Redirection Policy:   $StatusTeamsRedirPol"
    Write-Output "WARN:        Status Machine Installation:       $StatusMachineInstall"
    Write-Output "WARN:        Status Teams Running:              $StatusTeamsRunning"
    Write-Output "WARN:        Status HDX Redirection:            $StatusHdxRedir"
    Write-Output "WARN:        Status VC WebRTC Channel:          $StatusVCWebRtc"
}

